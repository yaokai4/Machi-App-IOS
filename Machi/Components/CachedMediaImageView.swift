import SwiftUI

struct CachedMediaImageView: View {
    @Environment(\.appLanguage) private var language
    let url: URL?
    var targetPixelSize: CGFloat = 900

    @State private var image: UIImage?
    @State private var failed = false
    @State private var reloadToken = UUID()
    @State private var loadedURL: URL?
    @State private var loadedPixelSize: CGFloat = 0

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                VStack(spacing: KXSpacing.xs) {
                    Image(systemName: "photo")
                        .font(.title3.weight(.semibold))
                    Button {
                        failed = false
                        reloadToken = UUID()
                    } label: {
                        Label(L("retry", language), systemImage: "arrow.clockwise")
                            .font(KXTypography.tiny.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KXColor.softBackground)
            } else {
                RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                    .fill(KXColor.softBackground)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.82)
                    }
                    .redacted(reason: .placeholder)
            }
        }
        .task(id: loadKey) {
            await load()
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

        let isSameRequest = loadedURL == url && Int(loadedPixelSize.rounded()) == Int(targetPixelSize.rounded())
        if !isSameRequest {
            failed = false
        }

        if let loaded = await ImageCacheService.shared.image(for: url, targetPixelSize: targetPixelSize) {
            image = loaded
            loadedURL = url
            loadedPixelSize = targetPixelSize
            failed = false
        } else {
            if !isSameRequest {
                image = nil
                loadedURL = nil
            }
            failed = true
        }
    }
}
