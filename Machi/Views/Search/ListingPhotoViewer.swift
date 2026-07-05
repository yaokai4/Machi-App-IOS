import SwiftUI
import Photos

/// 城市房源相册的全屏查看器:左右滑动、双指缩放/平移、双击放大,并可把当前
/// (全分辨率)图片保存到系统相册。复用 MediaPreviewView 里的 ZoomableMediaImage。
struct ListingPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    let media: [KaiXListingMediaDTO]

    @State private var selection: Int
    @State private var saveState: SaveState = .idle

    enum SaveState: Equatable { case idle, saving, saved, failed, denied }

    init(media: [KaiXListingMediaDTO], startIndex: Int) {
        self.media = media
        let clamped = media.isEmpty ? 0 : max(0, min(startIndex, media.count - 1))
        _selection = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(media.enumerated()), id: \.offset) { index, item in
                    Group {
                        // 全分辨率原图优先(转存时已存原图);拿不到再退回预览图。
                        if let url = item.sourceURL ?? item.previewURL {
                            ZoomableMediaImage(url: url, targetPixelSize: 4096)
                        } else {
                            Color.black
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            topChrome
            bottomChrome
        }
        .statusBarHidden(true)
        .onChange(of: selection) { _, _ in
            if saveState != .saving { saveState = .idle }
        }
    }

    private var topChrome: some View {
        VStack {
            HStack {
                if media.count > 1 {
                    Text("\(selection + 1)/\(media.count)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, KXSpacing.md)
                        .frame(height: 34)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55))
                        .clipShape(Circle())
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 18)
            Spacer()
        }
    }

    private var bottomChrome: some View {
        VStack {
            Spacer()
            Button {
                Task { await saveCurrent() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: saveIcon)
                    Text(saveLabel)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, KXSpacing.lg)
                .frame(height: 40)
                .background(.black.opacity(0.55), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(saveState == .saving || media.isEmpty)
            .padding(.bottom, 30)
        }
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
        case .idle: return KXListingCopy.pickText(language, "保存到相册", "アルバムに保存", "Save photo")
        case .saving: return KXListingCopy.pickText(language, "保存中…", "保存中…", "Saving…")
        case .saved: return KXListingCopy.pickText(language, "已保存", "保存しました", "Saved")
        case .failed: return KXListingCopy.pickText(language, "保存失败,重试", "保存失敗、再試行", "Failed, retry")
        case .denied: return KXListingCopy.pickText(language, "去设置开启相册权限", "設定で写真権限を許可", "Enable Photos access")
        }
    }

    private func saveCurrent() async {
        guard media.indices.contains(selection),
              let url = media[selection].sourceURL ?? media[selection].previewURL else { return }
        saveState = .saving
        let result = await ListingPhotoSaver.save(from: url)
        saveState = result
        if result == .saved {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if saveState == result, result != .saving { saveState = .idle }
    }
}

/// 下载图片字节并写入系统相册(仅需 add-only 权限)。
enum ListingPhotoSaver {
    static func save(from url: URL) async -> ListingPhotoViewer.SaveState {
        let data: Data
        do {
            let (bytes, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failed
            }
            guard UIImage(data: bytes) != nil else { return .failed }
            data = bytes
        } catch {
            return .failed
        }

        let status: PHAuthorizationStatus = await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { cont.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else { return .denied }

        return await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { ok, _ in
                cont.resume(returning: ok ? .saved : .failed)
            }
        }
    }
}
