import Foundation
import ImageIO
import UIKit

actor ImageCacheService {
    static let shared = ImageCacheService()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [NSString: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 220
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL, targetPixelSize: CGFloat = 900) async -> UIImage? {
        let key = "\(url.absoluteString)|\(Int(targetPixelSize.rounded()))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task(priority: .utility) {
            if url.isFileURL {
                return Self.downsampleImage(at: url, maxPixelSize: targetPixelSize)
            }
            return await Self.downsampleRemoteImage(at: url, maxPixelSize: targetPixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    func clear() {
        cache.removeAllObjects()
        inFlight.removeAll()
    }

    private static func downsampleImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        return downsampleImage(source: source, maxPixelSize: maxPixelSize)
    }

    /// Dedicated session for image downloads. URLSession.shared defaults to a
    /// 60s request timeout, so on a weak network (e.g. 国内弱网) a tile would
    /// shimmer for a full minute before the retry placeholder appears — which
    /// reads as "stuck forever". A bounded 18s request / 30s resource timeout
    /// surfaces the tappable retry state quickly instead. waitsForConnectivity
    /// is off so an offline tap fails fast rather than hanging.
    private static let downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 18
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static func downsampleRemoteImage(at url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        do {
            let (data, response) = try await downloadSession.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }
            return downsampleImage(data: data, maxPixelSize: maxPixelSize)
        } catch {
            return nil
        }
    }

    private static func downsampleImage(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        return downsampleImage(source: source, maxPixelSize: maxPixelSize)
    }

    private static func downsampleImage(source: CGImageSource, maxPixelSize: CGFloat) -> UIImage? {
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
