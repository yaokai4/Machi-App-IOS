import AVKit
import SwiftUI

struct CachedMediaImageView: View {
    @Environment(\.appLanguage) private var language
    let url: URL?
    var targetPixelSize: CGFloat = 900
    var failureMode: CachedMediaImageFailureMode = .quietPlaceholder
    var contentMode: ContentMode = .fill
    /// Stable cache identity for private/signed attachments whose URL rotates on
    /// re-sign (attachmentId / objectKey). Nil for public URLs.
    var stableKey: String? = nil
    /// Re-sign hook for a private attachment: called once when the current
    /// (likely expired) signed URL fails to load, so the view can fetch a fresh
    /// URL and retry — instead of endlessly replaying a dead URL. Returns the
    /// new URL, or nil if re-signing failed.
    var onResign: (() async -> URL?)? = nil

    @State private var image: UIImage?
    @State private var failed = false
    @State private var reloadToken = UUID()
    @State private var loadedURL: URL?
    @State private var loadedPixelSize: CGFloat = 0
    /// The freshest URL to actually load — starts as `url`, and is replaced by a
    /// re-signed URL after a load failure so the retry hits a live URL. Reset
    /// whenever the upstream `url` changes.
    @State private var effectiveURL: URL?
    @State private var didAttemptResign = false

    var body: some View {
        ZStack {
            if image == nil && !failed {
                MediaLoadingSkeleton()
            }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
            if failed {
                failureView
            }
        }
        // Cold loads cross-fade in (the `withAnimation` in `load()` drives the
        // Image's `.transition(.opacity)`); a memory-cache hit paints instantly
        // with no animation, so scrolling back to a seen tile doesn't re-trigger
        // a fade or churn animation transactions on the scroll's hot path.
        .task(id: loadKey) {
            await load()
        }
    }

    @ViewBuilder
    private var failureView: some View {
        switch failureMode {
        case .transparent:
            Color.clear
        case .quietPlaceholder:
            Button {
                failed = false
                reloadToken = UUID()
            } label: {
                ZStack {
                    KXColor.softBackground
                    VStack(spacing: KXSpacing.sm) {
                        Image(systemName: "photo")
                            .font(.title3.weight(.semibold))
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.secondary.opacity(0.56))
                }
            }
            .buttonStyle(.plain)
            // 图标-only 重试按钮:旁白只能念出 SF Symbol 名,须给三语标签。
            .accessibilityLabel(KXListingCopy.pickText(language, "图片加载失败，点击重试", "画像を読み込めませんでした。タップして再試行", "Image failed to load — tap to retry"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // The upstream `url` and the pixel size drive a reload; the re-signed
    // `effectiveURL` is tracked separately so a re-sign swaps the source without
    // re-keying the whole `.task`. `stableKey` is folded in so two different
    // signed URLs for the same attachment don't force separate loads.
    private var loadKey: String {
        "\(url?.absoluteString ?? "nil")|\(stableKey ?? "")|\(Int(targetPixelSize.rounded()))|\(reloadToken.uuidString)"
    }

    private func load() async {
        // A fresh upstream URL (or key change) invalidates any prior re-sign.
        if effectiveURL == nil || loadedURL != url {
            effectiveURL = url
            didAttemptResign = false
        }
        guard let target = effectiveURL else {
            image = nil
            loadedURL = nil
            failed = true
            return
        }

        // Fast path: synchronous memory-cache hit → paint immediately, no fade.
        // This is the common case when a recycled cell scrolls back into view.
        if let cached = ImageCacheService.shared.cachedImageSync(for: target, targetPixelSize: targetPixelSize, stableKey: stableKey) {
            image = cached
            loadedURL = url
            loadedPixelSize = targetPixelSize
            failed = false
            return
        }

        let isSameRequest = loadedURL == url && Int(loadedPixelSize.rounded()) == Int(targetPixelSize.rounded())
        if !isSameRequest {
            failed = false
        }

        let requestedPixelSize = targetPixelSize
        if let loaded = await ImageCacheService.shared.image(for: target, targetPixelSize: requestedPixelSize, stableKey: stableKey) {
            guard !Task.isCancelled else { return }
            // Cold load (disk/network): reveal with a gentle cross-fade.
            withAnimation(.easeOut(duration: 0.2)) {
                image = loaded
            }
            loadedURL = url
            loadedPixelSize = requestedPixelSize
            failed = false
            return
        }

        guard !Task.isCancelled else { return }

        // The signed URL likely expired (403/expired) — re-sign once and retry
        // against a live URL rather than surfacing a dead-URL failure state.
        if let onResign, !didAttemptResign {
            didAttemptResign = true
            if let fresh = await onResign() {
                guard !Task.isCancelled else { return }
                effectiveURL = fresh
                if let loaded = await ImageCacheService.shared.image(for: fresh, targetPixelSize: requestedPixelSize, stableKey: stableKey) {
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        image = loaded
                    }
                    loadedURL = url
                    loadedPixelSize = requestedPixelSize
                    failed = false
                    // Re-arm the re-sign for this view instance. `loadedURL == url`
                    // after a successful re-sign, so the load()-top reset guard
                    // (effectiveURL == nil || loadedURL != url) won't clear this
                    // flag on a later load. Without re-arming here, if both image
                    // caches get evicted AND this freshly-signed URL later expires,
                    // the next load would skip re-signing and paint a dead-URL
                    // failure — breaking the "never replay a dead URL" guarantee.
                    didAttemptResign = false
                    return
                }
            }
        }

        guard !Task.isCancelled else { return }
        if !isSameRequest {
            image = nil
            loadedURL = nil
        }
        failed = true
    }
}

enum CachedMediaImageFailureMode {
    case quietPlaceholder
    case transparent
}

/// Quiet placeholder shown while media decodes — a slow opacity breath
/// instead of the old light-sweep, which flashed white on every refresh.
/// Reads well at any size, from a tiny grid thumbnail to a full-bleed cover.
private struct MediaLoadingSkeleton: View {
    var body: some View {
        LinearGradient(
            colors: [
                KXColor.softBackground.opacity(0.96),
                KXColor.elevatedBackground.opacity(0.74),
                KXColor.softBackground.opacity(0.9)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct MediaImageView: View {
    let url: URL?
    var targetPixelSize: CGFloat = 900
    var failureMode: CachedMediaImageFailureMode = .quietPlaceholder
    var contentMode: ContentMode = .fill
    var stableKey: String? = nil
    var onResign: (() async -> URL?)? = nil

    var body: some View {
        CachedMediaImageView(
            url: url,
            targetPixelSize: targetPixelSize,
            failureMode: failureMode,
            contentMode: contentMode,
            stableKey: stableKey,
            onResign: onResign
        )
    }
}

struct MediaVideoView: View {
    @Environment(\.appLanguage) private var language

    let sourceURL: URL?
    let posterURL: URL?
    var autoPlay = false
    /// Stable cache identity + re-sign hook for a PRIVATE DM video poster whose
    /// signed URL rotates. Nil for public covers (keyed by URL, no re-sign).
    var posterStableKey: String? = nil
    var posterOnResign: (() async -> URL?)? = nil
    /// 视频正文的重签钩子(复用 MessageRepository.resignAttachmentURL)。私密
    /// DM 视频的签名 URL 约 4 分钟过期;轮询暂停时(搜索/日期过滤激活)没有人
    /// 保鲜,播放失败后的重试若仍用同一个死 URL 会永远失败,看起来像视频损坏。
    /// 有此钩子时,重试先重签一次再重建 player。公开视频保持 nil。
    var bodyOnResign: (() async -> URL?)? = nil

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playbackFailed = false
    /// The URL the current player item was built from — lets a URL rotation swap
    /// the item + seek (preserving position) instead of rebuilding the player.
    @State private var loadedSourceURL: URL?

    var body: some View {
        ZStack {
            if isPlaying, sourceURL != nil {
                VideoPlayer(player: player)
                    .background(Color.black)
            } else {
                if let posterURL {
                    MediaImageView(url: posterURL, targetPixelSize: 1400, stableKey: posterStableKey, onResign: posterOnResign)
                        .transition(.opacity)
                } else {
                    ZStack {
                        Color(red: 0.055, green: 0.071, blue: 0.102)
                        VStack(spacing: 10) {
                            Image(systemName: playbackFailed ? "exclamationmark.arrow.triangle.2.circlepath" : "video.fill")
                                .kxScaledFont(36, weight: .bold)
                            Text(playbackFailed ? L("videoLoadFailedRetry", language) : L("video", language))
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.white.opacity(0.82))
                    }
                }
                if sourceURL != nil {
                    Button {
                        let isRetry = playbackFailed
                        playbackFailed = false
                        // 播放失败后的重试:签名 URL 大概率已过期,先重签拿到
                        // 活 URL 再重建播放器,而不是重放同一个死 URL。
                        if isRetry, let bodyOnResign {
                            Task { @MainActor in
                                let fresh = await bodyOnResign()
                                configurePlayer(with: fresh ?? sourceURL, shouldPlay: true)
                            }
                        } else {
                            configurePlayer(shouldPlay: true)
                        }
                    } label: {
                        Image(systemName: playbackFailed ? "arrow.clockwise" : "play.fill")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(.black.opacity(0.62), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
                            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playbackFailed ? L("retryVideo", language) : L("playVideo", language))
                }
            }
        }
        .clipped()
        .task(id: sourceURL?.absoluteString ?? "nil") {
            guard autoPlay else {
                player?.pause()
                player = nil
                isPlaying = false
                playbackFailed = false
                loadedSourceURL = nil
                return
            }
            // If we're already playing this attachment and only the *signed URL*
            // changed (rotation), swap the underlying item and seek back to the
            // current position instead of tearing the player down and restarting
            // from 0 — the viewer never sees a flash-to-start.
            if let player, isPlaying, loadedSourceURL != nil, let sourceURL {
                let resumeAt = player.currentTime()
                let item = AVPlayerItem(url: sourceURL)
                player.replaceCurrentItem(with: item)
                if resumeAt.isNumeric, resumeAt > .zero {
                    player.seek(to: resumeAt, toleranceBefore: .zero, toleranceAfter: .zero)
                }
                player.play()
                loadedSourceURL = sourceURL
                return
            }
            configurePlayer(shouldPlay: autoPlay)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { note in
            guard let currentItem = player?.currentItem,
                  let failedItem = note.object as? AVPlayerItem,
                  failedItem === currentItem
            else { return }
            player?.pause()
            isPlaying = false
            playbackFailed = true
        }
        .onDisappear {
            player?.pause()
            player = nil
            isPlaying = false
            loadedSourceURL = nil
        }
    }

    /// `overrideURL`:重签得到的新 URL(见重试按钮)。默认沿用 sourceURL。
    @MainActor
    private func configurePlayer(with overrideURL: URL? = nil, shouldPlay: Bool) {
        player?.pause()
        guard let target = overrideURL ?? sourceURL else {
            player = nil
            isPlaying = false
            loadedSourceURL = nil
            return
        }
        let nextPlayer = AVPlayer(url: target)
        player = nextPlayer
        loadedSourceURL = target
        isPlaying = shouldPlay
        playbackFailed = false
        if shouldPlay {
            nextPlayer.play()
        }
    }
}
