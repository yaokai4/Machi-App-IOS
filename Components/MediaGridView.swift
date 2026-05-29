import SwiftUI

struct MediaGridView: View {
    @EnvironmentObject private var chrome: AppChromeState
    let mediaItems: [MediaEntity]
    @State private var selectedMedia: MediaEntity?

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
                        ZStack(alignment: .bottomTrailing) {
                            if let url = item.displayURL {
                                CachedMediaImageView(url: url, targetPixelSize: mediaItems.count == 1 ? 900 : 560)
                                    .frame(height: height)
                                    .clipped()
                            } else {
                                MediaPlaceholderTile(item: item, height: height)
                            }

                            if item.type == .video {
                                Label(durationText(item.duration), systemImage: "play.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, KXSpacing.sm)
                                    .padding(.vertical, KXSpacing.xs)
                                    .background {
                                        Capsule()
                                            .fill(.black.opacity(0.24))
                                            .glassEffect(KXGlass.control, in: Capsule())
                                    }
                                    .clipShape(Capsule())
                                    .padding(KXSpacing.sm)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .fullScreenCover(item: $selectedMedia) { media in
                MediaPreviewView(media: media)
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

        let ratio = CGFloat(item.height / max(item.width, 1))
        return min(max(156, 220 * ratio), item.type == .video ? 206 : 232)
    }
}

private struct MediaPlaceholderTile: View {
    let item: MediaEntity
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color.kaixNamed(item.placeholderColorName.isEmpty ? "green" : item.placeholderColorName).opacity(0.86),
                    Color.black.opacity(0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: item.placeholderSymbol.isEmpty ? "photo.fill" : item.placeholderSymbol)
                .font(.system(size: KXIconSize.lg + 6, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
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
