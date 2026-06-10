import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

actor UploadService {
    static let shared = UploadService()

    enum UploadError: Error {
        case invalidMedia
        case writeFailed
        case thumbnailFailed
    }

    func prepareImage(data: Data) async throws -> MediaDraft {
        let id = UUID().uuidString
        let directory = try mediaDirectory()
        let fileName = "\(id).jpg"
        let imageURL = directory.appendingPathComponent(fileName)
        let thumbnailURL = directory.appendingPathComponent("\(id)-thumb.jpg")

        guard let compressed = encodedJPEG(from: data, maxPixel: 1600, quality: 0.78),
              let thumbnail = encodedJPEG(from: data, maxPixel: 640, quality: 0.72)
        else {
            throw UploadError.invalidMedia
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
            duration: 0
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

        let asset = AVURLAsset(url: videoURL)
        let durationTime = (try? await asset.load(.duration)) ?? .zero
        let duration = CMTimeGetSeconds(durationTime).isFinite ? CMTimeGetSeconds(durationTime) : 0
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
            width: thumbnail.size.width,
            height: thumbnail.size.height,
            duration: duration
        )
    }

    func upload(
        draft: MediaDraft,
        purpose: String,
        entityType: String
    ) async throws -> KaiXMediaDTO {
        let data: Data
        do {
            data = try Data(contentsOf: draft.localURL)
        } catch {
            throw UploadError.writeFailed
        }

        let uploaded = try await KaiXAPIClient.shared.uploadFile(
            data: data,
            mime: draft.contentType,
            fileName: draft.fileName,
            purpose: purpose,
            entityType: entityType,
            width: Int(draft.width),
            height: Int(draft.height),
            duration: draft.duration
        )
        return uploaded.media
    }

    private func mediaDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("KaiXMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
