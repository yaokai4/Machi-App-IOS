import SwiftUI

struct MediaPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    let mediaItems: [MediaEntity]
    let initialMediaID: String

    @State private var selection: String
    @State private var originalImageIDs: Set<String> = []

    init(mediaItems: [MediaEntity], initialMediaID: String) {
        self.mediaItems = mediaItems
        self.initialMediaID = initialMediaID
        _selection = State(initialValue: initialMediaID)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(mediaItems) { item in
                    mediaPage(item)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            topChrome
            bottomChrome
        }
        .onAppear {
            if !mediaItems.contains(where: { $0.id == selection }) {
                selection = mediaItems.first?.id ?? initialMediaID
            }
        }
    }

    @ViewBuilder
    private func mediaPage(_ media: MediaEntity) -> some View {
        if media.type == .video {
            MediaVideoView(
                sourceURL: media.sourceURL,
                posterURL: media.previewURL,
                autoPlay: selection == media.id,
                posterStableKey: media.posterStableCacheKey,
                posterOnResign: posterResignHandler(for: media),
                // 私密 DM 视频正文的重签钩子:签名 URL 过期后重试不再重放死 URL
                bodyOnResign: resignHandler(for: media)
            )
                .padding()
        } else if let url = imageURL(for: media) {
            ZoomableMediaImage(
                url: url,
                targetPixelSize: originalImageIDs.contains(media.id) ? 4096 : 1800,
                stableKey: media.stableCacheKey,
                onResign: resignHandler(for: media)
            )
            // Anchor identity on the media (and the original-vs-preview toggle),
            // NOT the URL: a signed-URL rotation then swaps the image source in
            // place instead of tearing the view down and resetting the pan/zoom
            // the user set up. Switching to the original still rebuilds (its
            // target pixel size genuinely changes).
            .id("\(media.id)-\(originalImageIDs.contains(media.id))")
        } else {
            VStack(spacing: KXSpacing.lg) {
                Image(systemName: media.placeholderSymbol.isEmpty ? "photo.fill" : media.placeholderSymbol)
                    .kxScaledFont(72, weight: .bold)
                Text(media.placeholderTitle.isEmpty ? L("mediaPreview", language) : media.placeholderTitle)
                    .font(.title2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.kaixNamed(media.placeholderColorName).opacity(0.8), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var topChrome: some View {
        VStack {
            HStack {
                Text(counterText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, KXSpacing.md)
                    .frame(height: 34)
                    .background(.black.opacity(0.45), in: Capsule())

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55))
                        .clipShape(Circle())
                }
                // 图标-only 关闭按钮:旁白只能念出符号名,须给三语标签。
                .accessibilityLabel(KXListingCopy.pickText(language, "关闭", "閉じる", "Close"))
            }
            .padding(.top, 18)
            .padding(.horizontal, 18)
            Spacer()
        }
    }

    @ViewBuilder
    private var bottomChrome: some View {
        if let current = currentMedia, current.type == .image, current.sourceURL != nil {
            VStack {
                Spacer()
                Button {
                    originalImageIDs.insert(current.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: originalImageIDs.contains(current.id) ? "checkmark.circle.fill" : "arrow.down.circle")
                        // 无既有 L() 键,按仓库惯例用内联三语(pickText),
                        // 不能写死中文——ja/en 用户也会看到这个按钮。
                        Text(originalImageIDs.contains(current.id)
                            ? KXListingCopy.pickText(language, "已加载原图", "元画像を読み込み済み", "Original loaded")
                            : KXListingCopy.pickText(language, "查看原图", "元画像を表示", "View original"))
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.black.opacity(0.55), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 28)
            }
        }
    }

    private var currentMedia: MediaEntity? {
        mediaItems.first { $0.id == selection }
    }

    private var counterText: String {
        guard let index = mediaItems.firstIndex(where: { $0.id == selection }) else {
            return mediaItems.isEmpty ? "0/0" : "1/\(mediaItems.count)"
        }
        return "\(index + 1)/\(mediaItems.count)"
    }

    private func imageURL(for media: MediaEntity) -> URL? {
        if originalImageIDs.contains(media.id) {
            return media.sourceURL ?? media.mediumSourceURL ?? media.displayURL
        }
        return media.mediumSourceURL ?? media.displayURL ?? media.sourceURL
    }

    /// Re-sign handler for a private DM attachment (identified by a non-empty
    /// stable cache key). `postId` carries the message id and `id` the
    /// attachment id. Public media (posts, listings) returns nil — nothing to
    /// re-sign. Rebuilds the entity's URLs isn't needed here; the loader just
    /// needs a fresh live URL to retry with.
    private func resignHandler(for media: MediaEntity) -> (() async -> URL?)? {
        guard media.stableCacheKey != nil, !media.postId.isEmpty else { return nil }
        let messageId = media.postId
        let attachmentId = media.remoteId ?? media.id
        return {
            guard let fresh = await MessageRepository.resignAttachmentURL(messageId: messageId, attachmentId: attachmentId) else { return nil }
            return URL(string: fresh)
        }
    }

    /// Re-sign handler for a PRIVATE DM video poster (non-empty poster stable
    /// cache key). Nil for public covers / non-DM media.
    private func posterResignHandler(for media: MediaEntity) -> (() async -> URL?)? {
        guard media.posterStableCacheKey != nil, !media.postId.isEmpty else { return nil }
        let messageId = media.postId
        let attachmentId = media.remoteId ?? media.id
        return {
            guard let fresh = await MessageRepository.resignPosterURL(messageId: messageId, attachmentId: attachmentId) else { return nil }
            return URL(string: fresh)
        }
    }
}

/// Full-screen image with pinch-zoom, drag-pan and double-tap toggle so long
/// screenshots can actually be read. Reused by the listing photo viewer.
struct ZoomableMediaImage: View {
    let url: URL
    let targetPixelSize: CGFloat
    var stableKey: String? = nil
    var onResign: (() async -> URL?)? = nil

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            zoomableImage(in: proxy.size)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func zoomableImage(in size: CGSize) -> some View {
        let base = MediaImageView(url: url, targetPixelSize: targetPixelSize, contentMode: .fit, stableKey: stableKey, onResign: onResign)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnificationGesture)
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.22)) {
                    if scale > 1 {
                        resetZoom()
                    } else {
                        scale = 2.6
                        lastScale = 2.6
                    }
                }
            }

        if scale > 1.01 {
            base.simultaneousGesture(panGesture)
        } else {
            base
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.02 { resetZoom() }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func resetZoom() {
        withAnimation(.snappy(duration: 0.2)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }
}
