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
            // 朋友圈式预览:所有卡片都用固定正方形裁切,点开后再看完整比例。
            let columnCount = count == 1 ? 1 : (count == 2 || count == 4 ? 2 : 3)
            let tileSpacing: CGFloat = 4
            let columns = Array(repeating: GridItem(.flexible(), spacing: tileSpacing), count: columnCount)

            LazyVGrid(columns: columns, spacing: tileSpacing) {
                ForEach(mediaItems) { item in
                    Button {
                        selectedMedia = item
                    } label: {
                        ZStack {
                            if let url = item.displayURL ?? item.mediumSourceURL ?? item.sourceURL {
                                MediaImageView(
                                    url: url,
                                    targetPixelSize: count == 1 ? 960 : 640,
                                    contentMode: .fill
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
                        .modifier(MediaTileShape())
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

}

/// Feed 预览始终用 1:1 方格。原图比例只在全屏预览里展示。
private struct MediaTileShape: ViewModifier {
    func body(content: Content) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
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
