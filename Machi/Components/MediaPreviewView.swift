import SwiftUI
import UIKit

struct MediaPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    let mediaItems: [MediaEntity]
    let initialMediaID: String

    @State private var selection: String
    @State private var originalImageIDs: Set<String> = []
    /// True while the visible image is pinch/double-tap zoomed in. Paging and
    /// drag-to-dismiss are both disabled in that state so the pan gesture owns
    /// every drag unambiguously.
    @State private var isZoomedIn = false
    /// Live translation of the swipe-down-to-close gesture. Content follows
    /// the finger, the black backdrop fades, and past the threshold the viewer
    /// dismisses — the muscle memory every photo viewer trains.
    @State private var dismissOffset: CGSize = .zero
    @State private var dismissDragAxis: DismissDragAxis?
    @State private var saveState: ListingPhotoViewer.SaveState = .idle
    @State private var isShowingSaveOptions = false

    private enum DismissDragAxis {
        case horizontal
        case vertical
    }

    init(mediaItems: [MediaEntity], initialMediaID: String) {
        self.mediaItems = mediaItems
        self.initialMediaID = initialMediaID
        _selection = State(initialValue: initialMediaID)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(mediaItems) { item in
                    mediaPage(item)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // 放大态禁用翻页:拖动放大后的图片不再误触翻页(与 ZoomableMediaImage
            // 内 highPriorityGesture 的 pan 互为双保险)。
            .scrollDisabled(isZoomedIn)
            .ignoresSafeArea()
            .offset(y: dismissOffset.height)
            .scaleEffect(dismissScale, anchor: .center)

            Group {
                topChrome
                bottomChrome
            }
            .opacity(chromeOpacity)
        }
        // 让下层界面透出来,下滑关闭时才有 Photos 式「内容跟手 + 背景渐隐」的
        // 退出感;不拖动时黑色背景不透明,观感与之前完全一致。
        .presentationBackground(.clear)
        .simultaneousGesture(dismissDragGesture)
        .onAppear {
            if !mediaItems.contains(where: { $0.id == selection }) {
                selection = mediaItems.first?.id ?? initialMediaID
            }
        }
        .onChange(of: selection) { _, _ in
            isZoomedIn = false
            if saveState != .saving { saveState = .idle }
        }
        .confirmationDialog(saveToAlbumText, isPresented: $isShowingSaveOptions, titleVisibility: .hidden) {
            Button(saveToAlbumText) {
                Task { await saveCurrentImage() }
            }
            Button(L("cancel", language), role: .cancel) {}
        }
    }

    // MARK: - Swipe down to close

    /// 0 → 1 progress of the swipe-down gesture, used to fade the backdrop
    /// and chrome while the content follows the finger.
    private var dismissProgress: CGFloat {
        min(max(dismissOffset.height, 0) / 320, 1)
    }

    private var backgroundOpacity: CGFloat {
        1 - dismissProgress * 0.72
    }

    private var dismissScale: CGFloat {
        1 - dismissProgress * 0.1
    }

    private var chromeOpacity: CGFloat {
        1 - min(dismissProgress * 2.4, 1)
    }

    /// Videos keep the X button only: a simultaneous vertical drag would fight
    /// the player's scrubber. Zoomed images hand every drag to the pan.
    private var canDragToDismiss: Bool {
        guard !isZoomedIn else { return false }
        return currentMedia?.type == .image
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { value in
                guard canDragToDismiss else { return }
                // 首次位移时锁方向:横向交给 TabView 翻页,纵向才进入关闭跟手,
                // 二者不会同时响应。
                if dismissDragAxis == nil {
                    dismissDragAxis = abs(value.translation.height) > abs(value.translation.width)
                        ? .vertical
                        : .horizontal
                }
                guard dismissDragAxis == .vertical else { return }
                let dy = max(0, value.translation.height)
                dismissOffset = CGSize(width: value.translation.width * 0.22, height: dy)
            }
            .onEnded { value in
                let axis = dismissDragAxis
                dismissDragAxis = nil
                guard canDragToDismiss, axis == .vertical else {
                    dismissOffset = .zero
                    return
                }
                // 距离或甩动速度任一超阈值即关闭,否则弹回原位。
                if value.translation.height > 140 || value.predictedEndTranslation.height > 300 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dismissOffset = .zero
                    }
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
                onResign: resignHandler(for: media),
                onZoomChanged: { zoomed in
                    if selection == media.id {
                        isZoomedIn = zoomed
                    }
                }
            )
            // Anchor identity on the media (and the original-vs-preview toggle),
            // NOT the URL: a signed-URL rotation then swaps the image source in
            // place instead of tearing the view down and resetting the pan/zoom
            // the user set up. Switching to the original still rebuilds (its
            // target pixel size genuinely changes).
            .id("\(media.id)-\(originalImageIDs.contains(media.id))")
            // 长按存图:租房户型图/优惠海报是高频存图场景,之前只能截屏。
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isShowingSaveOptions = true
            }
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
        if let current = currentMedia, current.type == .image {
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    if current.sourceURL != nil {
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
                    }

                    if imageURL(for: current) != nil {
                        Button {
                            Task { await saveCurrentImage() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: saveIcon)
                                Text(saveLabel)
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(.black.opacity(0.55), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(saveState == .saving)
                        .accessibilityLabel(saveLabel)
                    }
                }
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Save to album

    private var saveToAlbumText: String {
        KXListingCopy.pickText(language, "保存到相册", "アルバムに保存", "Save to Photos")
    }

    private var saveIcon: String {
        switch saveState {
        case .idle: return "square.and.arrow.down"
        case .saving: return "arrow.down.circle"
        case .saved: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .denied: return "lock.fill"
        }
    }

    private var saveLabel: String {
        switch saveState {
        case .idle: return saveToAlbumText
        case .saving: return KXListingCopy.pickText(language, "保存中…", "保存中…", "Saving…")
        case .saved: return KXListingCopy.pickText(language, "已保存", "保存しました", "Saved")
        case .failed: return KXListingCopy.pickText(language, "保存失败，重试", "保存失敗、再試行", "Failed, retry")
        case .denied: return KXListingCopy.pickText(language, "去设置开启相册权限", "設定で写真権限を許可", "Enable Photos access")
        }
    }

    /// Download the full-resolution bytes of the visible image and write them
    /// to the system photo library (add-only permission; the OS raises the
    /// permission sheet on first use). Reuses ListingPhotoSaver — same flow as
    /// the city-listing photo viewer.
    private func saveCurrentImage() async {
        guard let current = currentMedia, current.type == .image,
              let url = current.sourceURL ?? current.mediumSourceURL ?? current.displayURL else { return }
        saveState = .saving
        let result = await ListingPhotoSaver.save(from: url)
        saveState = result
        UINotificationFeedbackGenerator().notificationOccurred(result == .saved ? .success : .error)
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        if saveState == result, result != .saving { saveState = .idle }
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
///
/// Gesture contract:
/// - double tap zooms IN anchored at the tap point (so a corner of a long
///   screenshot lands centered, no follow-up dragging), and zooms OUT back
///   to fit;
/// - the pan is boundary-clamped to the scaled content with a rubber-band
///   overshoot that springs back on release — the image can no longer be
///   flung off screen;
/// - while zoomed the pan runs as a high-priority gesture and `onZoomChanged`
///   lets the host disable TabView paging, so dragging a zoomed image never
///   flips the page.
struct ZoomableMediaImage: View {
    let url: URL
    let targetPixelSize: CGFloat
    var stableKey: String? = nil
    var onResign: (() async -> URL?)? = nil
    /// Fires when the zoom state crosses the fit boundary (zoomed in <-> fit).
    var onZoomChanged: ((Bool) -> Void)? = nil

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5
    private let doubleTapScale: CGFloat = 2.6

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
            .gesture(magnificationGesture(in: size))
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                if scale > 1.01 {
                    resetZoom()
                } else {
                    zoomIn(at: location, in: size)
                }
            }

        // 放大后由高优先级 pan 接管拖动(否则与 TabView 翻页竞争);未放大时
        // 不挂 pan,竖向拖动才能落到外层的下滑关闭手势上。
        if scale > 1.01 {
            base.highPriorityGesture(panGesture(in: size))
        } else {
            base
        }
    }

    private func magnificationGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minScale), maxScale)
                // 缩小过程中同步收紧边界,松手时图片不会悬在界外。
                offset = clampedOffset(offset, scale: scale, in: size)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
                if scale <= 1.02 {
                    resetZoom()
                } else {
                    onZoomChanged?(true)
                }
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = rubberBandedOffset(proposed, scale: scale, in: size)
            }
            .onEnded { _ in
                let settled = clampedOffset(offset, scale: scale, in: size)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    offset = settled
                }
                lastOffset = settled
            }
    }

    /// Double-tap zoom anchored at the tap point: solve the offset that keeps
    /// the tapped content under the finger after scaling about the center.
    private func zoomIn(at location: CGPoint, in size: CGSize) {
        let k = doubleTapScale
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let anchored = CGSize(
            width: (center.x - location.x) * (k - 1),
            height: (center.y - location.y) * (k - 1)
        )
        withAnimation(.snappy(duration: 0.22)) {
            scale = k
            lastScale = k
            offset = clampedOffset(anchored, scale: k, in: size)
            lastOffset = offset
        }
        onZoomChanged?(true)
    }

    /// Hard boundary for the pan at a given scale: the scaled frame may not
    /// expose empty space past its edge (the same clamp Photos applies).
    private func clampedOffset(_ proposed: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let maxX = max(0, size.width * (scale - 1) / 2)
        let maxY = max(0, size.height * (scale - 1) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    /// Follow the finger past the boundary with 0.3 resistance; the pan's
    /// onEnded springs back to the hard clamp.
    private func rubberBandedOffset(_ proposed: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let hard = clampedOffset(proposed, scale: scale, in: size)
        return CGSize(
            width: hard.width + (proposed.width - hard.width) * 0.3,
            height: hard.height + (proposed.height - hard.height) * 0.3
        )
    }

    private func resetZoom() {
        withAnimation(.snappy(duration: 0.22)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
        onZoomChanged?(false)
    }
}
