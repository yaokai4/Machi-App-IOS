import CryptoKit
import Foundation
import ImageIO
import UIKit

actor ImageCacheService {
    static let shared = ImageCacheService()

    // NSCache is internally thread-safe, so it can be read from a nonisolated
    // context (see `cachedImageSync`) without hopping onto the actor.
    nonisolated(unsafe) private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [NSString: Task<UIImage?, Never>] = [:]
    /// Disk trim runs once per process, lazily on first access.
    private var didScheduleDiskTrim = false

    private init() {
        cache.countLimit = 220
        cache.totalCostLimit = 96 * 1024 * 1024
        // Release the decoded-bitmap cache under memory pressure. NSCache does
        // this on its own too, but being explicit guarantees the ~96 MB of
        // decoded images is dropped promptly (the purgeable disk copies survive).
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            ImageCacheService.shared.clearMemory()
        }
    }

    /// Drop only the in-memory decoded bitmaps (disk copies + in-flight decodes
    /// are kept). `cache` is `nonisolated(unsafe)` + thread-safe, so this is safe
    /// to call straight from the memory-warning notification.
    nonisolated func clearMemory() {
        cache.removeAllObjects()
    }

    /// `stableKey`, when provided, replaces the full URL as the cache identity —
    /// use it for private/signed attachments whose URL rotates on every re-sign
    /// (a URL-based key would miss on every rotation and re-download the same
    /// bytes). Pass the attachmentId / objectKey. Public URLs pass nil and keep
    /// the URL-based key.
    func image(for url: URL, targetPixelSize: CGFloat = 900, stableKey: String? = nil) async -> UIImage? {
        let identity = stableKey ?? url.absoluteString
        let key = "\(identity)|\(Int(targetPixelSize.rounded()))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }

        scheduleDiskTrimIfNeeded()

        let diskKey = Self.diskKey(identity: identity, targetPixelSize: targetPixelSize)
        // 必须 Task.detached:Task {} 的闭包带 @_inheritActorContext,会继承本
        // actor 的隔离,里面同步的 loadFromDisk(Data(contentsOf:) + 强制位图解码)
        // 就在 actor 上串行执行——滚动时每个磁盘命中都堵住其它 image(for:) 查询。
        // detached 才兑现下面注释承诺的 off-actor(与 clear/trimDisk 一致)。
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            // Disk read-through: a downsampled copy survives memory eviction and
            // cold launches, so a covered feed/avatar paints from local storage
            // instead of re-hitting the network. Runs off the actor (static,
            // nonisolated) so a slow read never serializes other lookups.
            if let onDisk = Self.loadFromDisk(diskKey) {
                return onDisk
            }
            let decoded: UIImage?
            if url.isFileURL {
                decoded = Self.downsampleImage(at: url, maxPixelSize: targetPixelSize)
            } else {
                decoded = await Self.downsampleRemoteImage(at: url, maxPixelSize: targetPixelSize)
            }
            if let decoded {
                Self.saveToDisk(decoded, diskKey: diskKey)
            }
            return decoded
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

    /// Synchronous memory-cache probe. Lets a view paint an already-decoded
    /// image in the same runloop tick — no `await` hop, no fade-in — for the
    /// very common case of a cell scrolling back into view. Misses (cold image)
    /// fall back to the async `image(for:)` path.
    nonisolated func cachedImageSync(for url: URL, targetPixelSize: CGFloat = 900, stableKey: String? = nil) -> UIImage? {
        let identity = stableKey ?? url.absoluteString
        let key = "\(identity)|\(Int(targetPixelSize.rounded()))" as NSString
        return cache.object(forKey: key)
    }

    func clear() {
        cache.removeAllObjects()
        inFlight.removeAll()
        Task.detached(priority: .utility) { Self.clearDisk() }
    }

    // MARK: - Prefetch (feed warm-up)

    /// One upcoming image the feed expects to need soon（下一页首图预热用）。
    /// `targetPixelSize` / `stableKey` must mirror the eventual on-screen
    /// request so the warmed entry hits the exact same cache key.
    struct PrefetchRequest: Sendable {
        let url: URL
        let targetPixelSize: CGFloat
        let stableKey: String?

        init(url: URL, targetPixelSize: CGFloat, stableKey: String? = nil) {
            self.url = url
            self.targetPixelSize = targetPixelSize
            self.stableKey = stableKey
        }
    }

    /// 静默预热：以 `.background` 优先级【串行】走正常 `image(for:)` 取图路径
    /// （内存 → 磁盘 → 网络，in-flight 去重共享），上屏加载永远优先；弱网下
    /// 预热排在队尾自然让路，不与可见磁贴争带宽。结果落进内存 + 磁盘两级
    /// 缓存，键与 CachedMediaImageView 的正常请求完全一致。
    nonisolated func prefetch(_ requests: [PrefetchRequest]) {
        guard !requests.isEmpty else { return }
        Task.detached(priority: .background) {
            for request in requests {
                _ = await ImageCacheService.shared.image(
                    for: request.url,
                    targetPixelSize: request.targetPixelSize,
                    stableKey: request.stableKey
                )
            }
        }
    }

    private func scheduleDiskTrimIfNeeded() {
        guard !didScheduleDiskTrim else { return }
        didScheduleDiskTrim = true
        Task.detached(priority: .background) { Self.trimDisk() }
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

    // MARK: - Disk cache

    /// Downsampled images persist here so a memory eviction or cold launch
    /// repaints from local storage. This is **not** authoritative data — it's a
    /// purgeable Caches-directory copy, age- and size-capped, that silently
    /// misses (callers fall back to the network) on any problem.
    private static let maxDiskAge: TimeInterval = 60 * 60 * 24 * 7   // 7 days
    private static let maxDiskBytes = 200 * 1024 * 1024              // 200 MB

    private static let diskDirectory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent("KaiXImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private static func diskKey(identity: String, targetPixelSize: CGFloat) -> String {
        let raw = "\(identity)|\(Int(targetPixelSize.rounded()))"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func diskFileURL(_ diskKey: String) -> URL? {
        diskDirectory?.appendingPathComponent("\(diskKey).img")
    }

    private static func loadFromDisk(_ diskKey: String) -> UIImage? {
        guard let url = diskFileURL(diskKey),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        guard Date().timeIntervalSince(modified) < maxDiskAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let image = UIImage(data: data)
        // Force the bitmap decode now, on this background task — otherwise
        // `UIImage(data:)` defers it to the first draw, which lands on the main
        // thread mid-scroll and shows up as a hitch on every disk-cache hit.
        return image?.preparingForDisplay() ?? image
    }

    private static func saveToDisk(_ image: UIImage, diskKey: String) {
        guard let url = diskFileURL(diskKey) else { return }
        // Preserve transparency (logos / stickers) with PNG; everything else
        // (the overwhelming majority — photos) goes JPEG for a fraction of the
        // bytes. The image is already downsampled, so this is small either way.
        let hasAlpha: Bool = {
            guard let alpha = image.cgImage?.alphaInfo else { return false }
            switch alpha {
            case .first, .last, .premultipliedFirst, .premultipliedLast: return true
            default: return false
            }
        }()
        let data = hasAlpha ? image.pngData() : image.jpegData(compressionQuality: 0.82)
        guard let data else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func clearDisk() {
        guard let dir = diskDirectory else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Drop expired files, then evict oldest-first until under the byte budget.
    /// Runs once per launch on a background task.
    private static func trimDisk() {
        guard let dir = diskDirectory else { return }
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
            if now.timeIntervalSince(date) >= maxDiskAge {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            living.append((file, date, values?.fileAllocatedSize ?? 0))
        }

        var total = living.reduce(0) { $0 + $1.size }
        guard total > maxDiskBytes else { return }
        for file in living.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
            if total <= maxDiskBytes { break }
        }
    }
}
