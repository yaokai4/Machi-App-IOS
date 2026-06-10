import SwiftUI

struct MediaPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    let media: MediaEntity

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if media.type == .video {
                MediaVideoView(sourceURL: media.sourceURL, posterURL: media.previewURL, autoPlay: true)
                    .padding()
            } else if let url = media.displayURL {
                ZoomableMediaImage(url: url)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: media.placeholderSymbol.isEmpty ? "photo.fill" : media.placeholderSymbol)
                        .font(.system(size: 72, weight: .bold))
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
            .padding(.top, 18)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}

/// Full-screen image with pinch-zoom, drag-pan and double-tap toggle so long
/// screenshots can actually be read (scaledToFit alone shrinks a 1:4 chat
/// capture into an unreadable strip).
private struct ZoomableMediaImage: View {
    let url: URL

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            MediaImageView(url: url, targetPixelSize: 1600)
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, 1), 5)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1.02 { resetZoom() }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
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
        }
        .ignoresSafeArea()
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
