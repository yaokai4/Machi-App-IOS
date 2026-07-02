import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

actor UploadService {
    static let shared = UploadService()
    private static let postImageUploadLimitBytes = 10 * 1024 * 1024
    private static let postVideoUploadLimitBytes = 200 * 1024 * 1024

    enum UploadError: Error {
        case invalidMedia
        case writeFailed
        case thumbnailFailed
        case mediaTooLarge
        case emptyMedia
        case uploadFailed
    }

    func prepareImage(data: Data) async throws -> MediaDraft {
        let id = UUID().uuidString
        let directory = try mediaDirectory()
        let fileName = "\(id).jpg"
        let imageURL = directory.appendingPathComponent(fileName)
        let thumbnailURL = directory.appendingPathComponent("\(id)-thumb.jpg")

        // 上传接近全分辨率(原来 1600px 偏糊):优先最长边 3072px、质量 0.9。
        // 若仍超过移动端上传上限,再逐级降档,避免服务端拒绝但不把所有图
        // 一刀切压糊。
        guard let thumbnail = encodedJPEG(from: data, maxPixel: 640, quality: 0.72) else {
            throw UploadError.invalidMedia
        }
        guard let compressed = encodedPublishJPEG(from: data) else {
            throw UploadError.mediaTooLarge
        }

        do {
            try compressed.data.write(to: imageURL, options: .atomic)
            try thumbnail.data.write(to: thumbnailURL, options: .atomic)
        } catch {
            throw UploadError.writeFailed
        }

        return MediaDraft(
            id: id,
            type: .image,
            localURL: imageURL,
            thumbnailURL: thumbnailURL,
            contentType: "image/jpeg",
            fileName: fileName,
            width: compressed.size.width,
            height: compressed.size.height,
            duration: 0,
            originalFileSize: data.count,
            uploadFileSize: compressed.data.count
        )
    }

    func prepareVideo(data: Data, contentType: UTType? = nil) async throws -> MediaDraft {
        let id = UUID().uuidString
        let directory = try mediaDirectory()
        let mime = normalizedVideoMIME(contentType?.preferredMIMEType, data: data)
        let fileName = "\(id).\(videoExtension(for: mime))"
        let videoURL = directory.appendingPathComponent(fileName)
        let thumbnailURL = directory.appendingPathComponent("\(id)-thumb.jpg")

        do {
            try data.write(to: videoURL, options: .atomic)
        } catch {
            throw UploadError.writeFailed
        }

        return try await finalizeVideoDraft(
            id: id,
            directory: directory,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            mime: mime,
            fileName: fileName,
            originalFileSize: data.count
        )
    }

    func prepareVideo(fileURL sourceURL: URL, contentType: UTType? = nil) async throws -> MediaDraft {
        let id = UUID().uuidString
        let directory = try mediaDirectory()
        let head = try await readPrefixData(at: sourceURL, maxBytes: 16)
        let mime = normalizedVideoMIME(contentType?.preferredMIMEType, data: head)
        let fileName = "\(id).\(videoExtension(for: mime))"
        let videoURL = directory.appendingPathComponent(fileName)
        let thumbnailURL = directory.appendingPathComponent("\(id)-thumb.jpg")

        do {
            if FileManager.default.fileExists(atPath: videoURL.path) {
                try FileManager.default.removeItem(at: videoURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: videoURL)
        } catch {
            throw UploadError.writeFailed
        }
        // The PhotosPicker transfer already made its own tmp copy under
        // MachiPickedVideos; now that we've re-staged it into KaiXMedia, drop
        // that intermediate so picked-video scratch doesn't pile up.
        cleanupPickedVideoSource(sourceURL)

        return try await finalizeVideoDraft(
            id: id,
            directory: directory,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            mime: mime,
            fileName: fileName,
            originalFileSize: fileSize(at: videoURL)
        )
    }

    private func finalizeVideoDraft(
        id: String,
        directory: URL,
        videoURL inputVideoURL: URL,
        thumbnailURL: URL,
        mime inputMime: String,
        fileName inputFileName: String,
        originalFileSize: Int
    ) async throws -> MediaDraft {
        var videoURL = inputVideoURL
        var mime = inputMime
        var fileName = inputFileName

        // 视频统一压到 ≤1080p(4K 也降到 1080p),或当源文件超过发布上限时
        // 尝试重新编码。转码失败会回退原片;最终仍超过 200MB 时再明确拒绝。
        if let capped = await transcodeTo1080pIfNeeded(
            sourceURL: videoURL,
            directory: directory,
            id: id,
            sourceByteCount: originalFileSize
        ) {
            try? FileManager.default.removeItem(at: videoURL)
            videoURL = capped
            mime = "video/mp4"
            fileName = capped.lastPathComponent
        }
        let uploadFileSize = fileSize(at: videoURL)
        guard uploadFileSize > 0 else {
            // A 0-byte file here means the source never fully materialized — most
            // often an iCloud video that hasn't finished downloading to the device,
            // or a transcode that produced no output. Stop now with a clear, retry-
            // able error instead of building a broken draft that only fails later
            // at upload time with an opaque message.
            throw UploadError.emptyMedia
        }
        guard uploadFileSize <= Self.postVideoUploadLimitBytes else {
            throw UploadError.mediaTooLarge
        }

        let asset = AVURLAsset(url: videoURL)
        let durationTime = (try? await asset.load(.duration)) ?? .zero
        let duration = CMTimeGetSeconds(durationTime).isFinite ? CMTimeGetSeconds(durationTime) : 0
        let videoSize = await videoPresentationSize(asset: asset)
        let thumbnail = await VideoThumbnailService.shared.thumbnail(for: videoURL) ?? videoPlaceholderThumbnail()
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.72) else {
            throw UploadError.thumbnailFailed
        }

        do {
            try thumbnailData.write(to: thumbnailURL, options: .atomic)
        } catch {
            throw UploadError.writeFailed
        }

        return MediaDraft(
            id: id,
            type: .video,
            localURL: videoURL,
            thumbnailURL: thumbnailURL,
            contentType: mime,
            fileName: fileName,
            width: videoSize.width,
            height: videoSize.height,
            duration: duration,
            originalFileSize: originalFileSize,
            uploadFileSize: uploadFileSize
        )
    }

    /// Re-encode a video to ≤1080p (mp4) when its longest side exceeds 1080.
    /// Returns the new file URL, or nil when no transcode is needed/possible
    /// (caller keeps the original — never blocks publishing).
    private func transcodeTo1080pIfNeeded(
        sourceURL: URL,
        directory: URL,
        id: String,
        sourceByteCount: Int
    ) async -> URL? {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize) else { return nil }
        let longest = Swift.max(abs(size.width), abs(size.height))
        guard longest > 1080 || sourceByteCount > Self.postVideoUploadLimitBytes else {
            return nil
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else { return nil }
        // CRITICAL: the output must never share the source's own path. An mp4
        // source is stored as "<id>.mp4"; using "<id>.mp4" here collided with it,
        // so the removeItem below deleted the very file we were transcoding. The
        // export then read a missing file and failed, and finalize fell back to a
        // now-0-byte "original" — which surfaced as "操作失败，请稍后重试" at upload
        // time and broke every mp4 video. Use a distinct suffix and bail if it
        // would ever still collide.
        let outURL = directory.appendingPathComponent("\(id)-1080p.mp4")
        guard outURL != sourceURL else { return nil }
        try? FileManager.default.removeItem(at: outURL)
        export.outputURL = outURL
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        guard export.status == .completed, FileManager.default.fileExists(atPath: outURL.path) else {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
        return outURL
    }

    func upload(
        draft: MediaDraft,
        purpose: String,
        entityType: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> KaiXMediaDTO {
        let metadata: [String: String]?
        if draft.type == .video {
            let thumbnailData: Data
            do {
                thumbnailData = try await loadFileData(at: draft.thumbnailURL)
            } catch {
                throw UploadError.thumbnailFailed
            }
            let cover = try await KaiXAPIClient.shared.uploadFile(
                data: thumbnailData,
                mime: "image/jpeg",
                fileName: "\(draft.id)-cover.jpg",
                purpose: "video_thumbnail",
                entityType: entityType,
                width: Int(draft.width),
                height: Int(draft.height)
            ) { progress in
                onProgress?(min(0.18, progress * 0.18))
            }
            metadata = ["thumbnailFileId": cover.file.id]
        } else {
            metadata = nil
        }

        let uploaded: (file: KaiXUploadedFileDTO, media: KaiXMediaDTO)
        if draft.type == .video {
            uploaded = try await KaiXAPIClient.shared.uploadFile(
                fileURL: draft.localURL,
                mime: draft.contentType,
                fileName: draft.fileName,
                purpose: purpose,
                entityType: entityType,
                width: Int(draft.width),
                height: Int(draft.height),
                duration: draft.duration,
                metadata: metadata
            ) { progress in
                onProgress?(0.18 + progress * 0.82)
            }
        } else {
            let data: Data
            do {
                data = try await loadFileData(at: draft.localURL)
            } catch {
                throw UploadError.writeFailed
            }
            uploaded = try await KaiXAPIClient.shared.uploadFile(
                data: data,
                mime: draft.contentType,
                fileName: draft.fileName,
                purpose: purpose,
                entityType: entityType,
                width: Int(draft.width),
                height: Int(draft.height),
                duration: draft.duration,
                metadata: metadata
            ) { progress in
                onProgress?(progress)
            }
        }
        return uploaded.media
    }

    private func mediaDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var directory = base.appendingPathComponent("KaiXMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Staged upload copies are reproducible scratch — never back them up to
        // iCloud (they'd bloat the backup and can't be restored usefully).
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory
    }

    /// Directory where staged media copies live (best-effort; nil if it can't be
    /// located). Used by the startup trim + draft cleanup.
    private func mediaDirectoryURL() -> URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("KaiXMedia", isDirectory: true)
    }

    /// Delete a draft's staged files (the upload copy + its poster/thumbnail)
    /// once they're no longer needed — after a successful send, or when the user
    /// removes the draft. Best-effort; a missing file is fine.
    func cleanupDraftFiles(_ draft: MediaDraft) {
        for url in [draft.localURL, draft.thumbnailURL] where url.isFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Remove the temporary copy PickedVideoFile made under
    /// tmp/MachiPickedVideos once the video has been re-staged into KaiXMedia,
    /// so the picked-file scratch doesn't accumulate.
    private func cleanupPickedVideoSource(_ url: URL) {
        guard url.isFileURL else { return }
        let pickedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MachiPickedVideos", isDirectory: true)
            .standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(pickedDir) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Startup housekeeping for the staged-media directory: drop files older
    /// than 48h, then, if the directory is still over 500 MB, evict oldest-first
    /// until under budget. Mirrors ImageCacheService.trimDisk. Idempotent and
    /// safe to call once per launch.
    func trimStagedMedia() {
        guard let dir = mediaDirectoryURL(),
              FileManager.default.fileExists(atPath: dir.path) else { return }
        let maxAge: TimeInterval = 48 * 60 * 60
        let maxBytes = 500 * 1024 * 1024
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileAllocatedSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        var living: [(url: URL, date: Date, size: Int)] = []
        for file in files {
            let values = try? file.resourceValues(forKeys: Set(keys))
            let date = values?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(date) >= maxAge {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            living.append((file, date, values?.fileAllocatedSize ?? 0))
        }

        var total = living.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        for file in living.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
            if total <= maxBytes { break }
        }
    }

    private func loadFileData(at url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: url)
        }.value
    }

    private func readPrefixData(at url: URL, maxBytes: Int) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: maxBytes) ?? Data()
        }.value
    }

    private func encodedJPEG(from data: Data, maxPixel: CGFloat, quality: CGFloat) -> (data: Data, size: CGSize)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let destinationOptions = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, destinationOptions)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return (output as Data, CGSize(width: cgImage.width, height: cgImage.height))
    }

    private func encodedPublishJPEG(from data: Data) -> (data: Data, size: CGSize)? {
        let attempts: [(CGFloat, CGFloat)] = [
            (3072, 0.9),
            (2400, 0.82),
            (2000, 0.76),
            (1600, 0.72)
        ]
        var fallback: (data: Data, size: CGSize)?
        for (maxPixel, quality) in attempts {
            guard let encoded = encodedJPEG(from: data, maxPixel: maxPixel, quality: quality) else { continue }
            fallback = encoded
            if encoded.data.count <= Self.postImageUploadLimitBytes {
                return encoded
            }
        }
        guard let fallback, fallback.data.count <= Self.postImageUploadLimitBytes else {
            return nil
        }
        return fallback
    }

    private func fileSize(at url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private func videoPresentationSize(asset: AVURLAsset) async -> CGSize {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else {
            return CGSize(width: 0, height: 0)
        }
        let transformed = natural.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    private func videoPlaceholderThumbnail() -> UIImage {
        let size = CGSize(width: 900, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.12, green: 0.17, blue: 0.26, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: -120, y: -80, width: 420, height: 420))
            UIColor(red: 0.16, green: 0.24, blue: 0.36, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 560, y: 560, width: 360, height: 360))
            UIColor.white.withAlphaComponent(0.92).setFill()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 390, y: 330))
            path.addLine(to: CGPoint(x: 390, y: 570))
            path.addLine(to: CGPoint(x: 600, y: 450))
            path.close()
            path.fill()
        }
    }

    private func normalizedVideoMIME(_ preferred: String?, data: Data) -> String {
        let bytes = Array(data.prefix(16))
        if bytes.count >= 12 {
            if bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
                let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
                return brand == "qt  " ? "video/quicktime" : "video/mp4"
            }
            if bytes[0] == 0x1A, bytes[1] == 0x45, bytes[2] == 0xDF, bytes[3] == 0xA3 {
                return "video/webm"
            }
        }
        let supported = ["video/mp4", "video/quicktime", "video/webm"]
        if let preferred = preferred?.lowercased(), supported.contains(preferred) {
            return preferred
        }
        return "video/mp4"
    }

    private func videoExtension(for mime: String) -> String {
        switch mime {
        case "video/quicktime": return "mov"
        case "video/webm": return "webm"
        default: return "mp4"
        }
    }
}

typealias UploadManager = UploadService
