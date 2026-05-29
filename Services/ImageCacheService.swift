import Foundation
import ImageIO
import UIKit

actor ImageCacheService {
    static let shared = ImageCacheService()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 220
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL, targetPixelSize: CGFloat = 900) async -> UIImage? {
        let key = "\(url.absoluteString)|\(Int(targetPixelSize.rounded()))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image: UIImage?
        if url.isFileURL {
            image = downsampleImage(at: url, maxPixelSize: targetPixelSize)
        } else {
            image = await downsampleRemoteImage(at: url, maxPixelSize: targetPixelSize)
        }
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    func clear() {
        cache.removeAllObjects()
    }

    private func downsampleImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        return downsampleImage(source: source, maxPixelSize: maxPixelSize)
    }

    private func downsampleRemoteImage(at url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }
            return downsampleImage(data: data, maxPixelSize: maxPixelSize)
        } catch {
            return nil
        }
    }

    private func downsampleImage(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        return downsampleImage(source: source, maxPixelSize: maxPixelSize)
    }

    private func downsampleImage(source: CGImageSource, maxPixelSize: CGFloat) -> UIImage? {
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
