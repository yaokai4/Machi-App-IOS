import AVFoundation
import UIKit

actor VideoThumbnailService {
    static let shared = VideoThumbnailService()

    private let cache = NSCache<NSURL, UIImage>()

    func thumbnail(for url: URL) async -> UIImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)

        for seconds in [0.2, 0.0, 1.0] {
            do {
                let cgImage = try await generateImage(with: generator, at: CMTime(seconds: seconds, preferredTimescale: 600))
                let image = UIImage(cgImage: cgImage)
                cache.setObject(image, forKey: key)
                return image
            } catch {
                continue
            }
        }
        return nil
    }

    func clear() {
        cache.removeAllObjects()
    }

    private func generateImage(with generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "KaiX.VideoThumbnail", code: -1))
                }
            }
        }
    }
}
