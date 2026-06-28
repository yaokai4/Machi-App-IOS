import AVKit
import SwiftUI

struct CachedMediaImageView: View {
    @Environment(\.appLanguage) private var language
    let url: URL?
    var targetPixelSize: CGFloat = 900
    var failureMode: CachedMediaImageFailureMode = .quietPlaceholder
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false
    @State private var reloadToken = UUID()
    @State private var loadedURL: URL?
    @State private var loadedPixelSize: CGFloat = 0

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
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.title3.weight(.semibold))
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.secondary.opacity(0.56))
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var loadKey: String {
        "\(url?.absoluteString ?? "nil")|\(Int(targetPixelSize.rounded()))|\(reloadToken.uuidString)"
    }

    private func load() async {
        guard let url else {
            image = nil
            loadedURL = nil
            failed = true
            return
        }

        // Fast path: synchronous memory-cache hit → paint immediately, no fade.
        // This is the common case when a recycled cell scrolls back into view.
        if let cached = ImageCacheService.shared.cachedImageSync(for: url, targetPixelSize: targetPixelSize) {
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

        let requestedURL = url
        let requestedPixelSize = targetPixelSize
        if let loaded = await ImageCacheService.shared.image(for: requestedURL, targetPixelSize: requestedPixelSize) {
            guard !Task.isCancelled else { return }
            // Cold load (disk/network): reveal with a gentle cross-fade.
            withAnimation(.easeOut(duration: 0.2)) {
                image = loaded
            }
            loadedURL = requestedURL
            loadedPixelSize = requestedPixelSize
            failed = false
        } else {
            guard !Task.isCancelled else { return }
            if !isSameRequest {
                image = nil
                loadedURL = nil
            }
            failed = true
        }
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

    var body: some View {
        CachedMediaImageView(url: url, targetPixelSize: targetPixelSize, failureMode: failureMode, contentMode: contentMode)
    }
}

struct MediaVideoView: View {
    @Environment(\.appLanguage) private var language

    let sourceURL: URL?
    let posterURL: URL?
    var autoPlay = false

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playbackFailed = false

    var body: some View {
        ZStack {
            if isPlaying, sourceURL != nil {
                VideoPlayer(player: player)
                    .background(Color.black)
            } else {
                if let posterURL {
                    MediaImageView(url: posterURL, targetPixelSize: 1400)
                        .transition(.opacity)
                } else {
                    ZStack {
                        Color(red: 0.055, green: 0.071, blue: 0.102)
                        VStack(spacing: 10) {
                            Image(systemName: playbackFailed ? "exclamationmark.arrow.triangle.2.circlepath" : "video.fill")
                                .font(.system(size: 36, weight: .bold))
                            Text(playbackFailed ? L("videoLoadFailedRetry", language) : L("video", language))
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.white.opacity(0.82))
                    }
                }
                if sourceURL != nil {
                    Button {
                        playbackFailed = false
                        configurePlayer(shouldPlay: true)
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
        }
    }

    @MainActor
    private func configurePlayer(shouldPlay: Bool) {
        player?.pause()
        guard let sourceURL else {
            player = nil
            isPlaying = false
            return
        }
        let nextPlayer = AVPlayer(url: sourceURL)
        player = nextPlayer
        isPlaying = shouldPlay
        playbackFailed = false
        if shouldPlay {
            nextPlayer.play()
        }
    }
}
