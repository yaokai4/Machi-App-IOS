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
            let columns = mediaItems.count == 1
                ? [GridItem(.flexible())]
                : [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(mediaItems) { item in
                    Button {
                        selectedMedia = item
                    } label: {
                        let height = mediaHeight(for: item)
                        ZStack {
                            if let url = item.displayURL {
                                MediaImageView(url: url, targetPixelSize: mediaItems.count == 1 ? 900 : 560)
                                    .frame(height: height)
                                    .clipped()
                            } else {
                                MediaPlaceholderTile(item: item, height: height)
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
                        .frame(height: height)
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
                        .clipShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .kxMatchedTransitionSource(id: item.id, in: mediaZoomNamespace)
                }
            }
            .fullScreenCover(item: $selectedMedia) { media in
                MediaPreviewView(media: media)
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

    private func mediaHeight(for item: MediaEntity) -> CGFloat {
        guard mediaItems.count == 1 else { return 112 }
        guard item.width > 0, item.height > 0 else {
            return item.type == .video ? 176 : 188
        }

        // Honor the real orientation: landscape stays compact, portrait is
        // allowed to grow tall enough that it doesn't read as a squashed
        // letterbox (full view lives in the media preview).
        let ratio = CGFloat(item.height / max(item.width, 1))
        return min(max(156, 220 * ratio), item.type == .video ? 300 : 340)
    }
}

private struct MediaPlaceholderTile: View {
    let item: MediaEntity
    let height: CGFloat

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
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}
