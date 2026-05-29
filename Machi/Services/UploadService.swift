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
        let imageURL = directory.appendingPathComponent("\(id).jpg")
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
            width: compressed.size.width,
            height: compressed.size.height,
            duration: 0
        )
    }

    func prepareVideo(data: Data) async throws -> MediaDraft {
        let id = UUID().uuidString
        let directory = try mediaDirectory()
        let videoURL = directory.appendingPathComponent("\(id).mov")
        let thumbnailURL = directory.appendingPathComponent("\(id)-thumb.jpg")

        do {
            try data.write(to: videoURL, options: .atomic)
        } catch {
            throw UploadError.writeFailed
        }

        let asset = AVURLAsset(url: videoURL)
        let durationTime = (try? await asset.load(.duration)) ?? .zero
        let duration = CMTimeGetSeconds(durationTime).isFinite ? CMTimeGetSeconds(durationTime) : 0
        guard let thumbnail = await VideoThumbnailService.shared.thumbnail(for: videoURL),
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.72)
        else {
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
            width: thumbnail.size.width,
            height: thumbnail.size.height,
            duration: duration
        )
    }

    func simulateUpload(mediaId: String) async -> Bool {
        try? await Task.sleep(nanoseconds: 250_000_000)
        return true
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
}
