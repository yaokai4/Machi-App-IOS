import SwiftUI

struct MediaGridView: View {
    @EnvironmentObject private var chrome: AppChromeState
    let mediaItems: [MediaEntity]
    @State private var selectedMedia: MediaEntity?
    // Photos-style zoom: the tapped tile is the literal source of the
    // full-screen viewer, so opening media reads as expansion, not a modal.
    @Namespace private var mediaZoomNamespace

    var body: some View {
        if !mediaItems.isEmpty {
            let count = mediaItems.count
            // 图片仍保持朋友圈式正方形预览；单个视频用更轻的横向
            // 16:10 卡片，减少 Feed 里的视觉压迫感。
            let columnCount = count == 1 ? 1 : (count == 2 || count == 4 ? 2 : 3)
            let tileSpacing: CGFloat = 4
            let columns = Array(repeating: GridItem(.flexible(), spacing: tileSpacing), count: columnCount)

            LazyVGrid(columns: columns, spacing: tileSpacing) {
                ForEach(mediaItems) { item in
                    Button {
                        selectedMedia = item
                    } label: {
                        ZStack {
                            if item.type == .video, let posterURL = item.displayURL {
                                // Video poster is a public CDN URL — no stable key.
                                MediaImageView(
                                    url: posterURL,
                                    targetPixelSize: count == 1 ? 960 : 640,
                                    contentMode: .fill
                                )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else if item.type == .video {
                                MediaPlaceholderTile(item: item, height: nil)
                            } else if let url = item.displayURL ?? item.mediumSourceURL ?? item.sourceURL {
                                MediaImageView(
                                    url: url,
                                    targetPixelSize: count == 1 ? 960 : 640,
                                    contentMode: .fill,
                                    stableKey: item.stableCacheKey,
                                    onResign: resignHandler(for: item)
                                )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else {
                                MediaPlaceholderTile(item: item, height: nil)
                            }

                            if item.type == .video {
                                // Centered play affordance over the poster/placeholder
                                // — parity with Web so a video always reads as tappable,
                                // not a still image.
                                Image(systemName: "play.fill")
                                    .font(.system(size: 17, weight: .black))
                                    .foregroundStyle(.white)
                                    .frame(width: 46, height: 46)
                                    .background(.black.opacity(0.5), in: Circle())
                                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                                    .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .modifier(MediaTileShape(aspectRatio: tileAspectRatio(for: item, count: count)))
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottomTrailing) {
                            if item.type == .video, item.duration > 0 {
                                Text(durationText(item.duration))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, KXSpacing.sm)
                                    .padding(.vertical, KXSpacing.xs)
                                    .background(Capsule().fill(.black.opacity(0.55)))
                                    .padding(KXSpacing.sm)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .kxMatchedTransitionSource(id: item.id, in: mediaZoomNamespace)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .fullScreenCover(item: $selectedMedia) { media in
                MediaPreviewView(mediaItems: mediaItems, initialMediaID: media.id)
                    .kxZoomTransition(sourceID: media.id, in: mediaZoomNamespace)
            }
            .onChange(of: selectedMedia) { _, media in
                chrome.setHidden(media != nil, reason: .mediaPreview)
            }
            .onDisappear {
                chrome.setHidden(false, reason: .mediaPreview)
            }
        }
    }

    private func durationText(_ duration: Double) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Re-sign handler for a private DM attachment (identified by a non-empty
    /// stable cache key). Nil for public post/listing media. `postId` = message
    /// id, `remoteId`/`id` = attachment id.
    private func resignHandler(for media: MediaEntity) -> (() async -> URL?)? {
        guard media.stableCacheKey != nil, !media.postId.isEmpty else { return nil }
        let messageId = media.postId
        let attachmentId = media.remoteId ?? media.id
        return {
            guard let fresh = await MessageRepository.resignAttachmentURL(messageId: messageId, attachmentId: attachmentId) else { return nil }
            return URL(string: fresh)
        }
    }

    private func tileAspectRatio(for item: MediaEntity, count: Int) -> CGFloat {
        // Multi-image grids keep the square rhythm; single media gets a
        // height-aware shape so the feed stays scannable.
        guard count == 1 else { return 1.0 }
        if item.type == .video { return 16.0 / 10.0 }
        return Self.singleImageAspectRatio(width: item.width, height: item.height)
    }

    /// Aspect ratio (width / height) for a lone feed photo. Uses the image's
    /// natural ratio — so a landscape food shot is shown short and uncropped
    /// instead of being force-squared — but clamps it to a comfortable window
    /// (4:5 portrait … 16:9 landscape) so a tall portrait can't dominate the
    /// card and a panorama can't shrink to a sliver. Unknown dimensions fall
    /// back to a calm 4:3.
    static func singleImageAspectRatio(width: Double, height: Double) -> CGFloat {
        let natural = (width > 0 && height > 0) ? CGFloat(width / height) : 4.0 / 3.0
        let minRatio: CGFloat = 4.0 / 5.0   // 0.80 — tallest allowed (portrait)
        let maxRatio: CGFloat = 16.0 / 9.0  // 1.78 — widest allowed (landscape)
        return min(max(natural, minRatio), maxRatio)
    }

}

/// Feed images keep the 1:1 grid rhythm; single videos are allowed to use
/// a wider preview so they read as video without dominating the card.
private struct MediaTileShape: ViewModifier {
    let aspectRatio: CGFloat

    func body(content: Content) -> some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { content }
            .clipped()
    }
}

private struct MediaPlaceholderTile: View {
    let item: MediaEntity
    let height: CGFloat?

    private var gradientColors: [Color] {
        if item.type == .video {
            // Premium brand-dark backdrop for videos without a first-frame poster
            // yet (legacy uploads / extraction failure) — never the flat green box
            // that read as "broken". Mirrors the Web fallbackVideoPoster gradient.
            return [
                Color(red: 0.059, green: 0.090, blue: 0.165),
                Color(red: 0.118, green: 0.227, blue: 0.541),
                Color(red: 0.059, green: 0.463, blue: 0.431)
            ]
        }
        let base = item.placeholderColorName.isEmpty ? "blue" : item.placeholderColorName
        return [Color.kaixNamed(base).opacity(0.86), Color.black.opacity(0.42)]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if item.type != .video {
                Image(systemName: item.placeholderSymbol.isEmpty ? "photo.fill" : item.placeholderSymbol)
                    .font(.system(size: KXIconSize.lg + 6, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }
            if !item.placeholderTitle.isEmpty {
                Text(item.placeholderTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(KXSpacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: height)
    }
}
