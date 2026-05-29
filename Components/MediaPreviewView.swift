import SwiftUI

struct MediaPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    let media: MediaEntity

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = media.displayURL {
                CachedMediaImageView(url: url, targetPixelSize: 1400)
                    .scaledToFit()
                    .padding()
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

            if media.type == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 72, weight: .black))
                    .foregroundStyle(.white.opacity(0.92))
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
