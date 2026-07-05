import SwiftUI
import UIKit

/// Interactive crop / reposition sheet used when a user picks a new avatar or
/// cover image. Instead of silently auto-cropping to a fixed region, the user
/// pans (drag) and zooms (pinch) the picked photo inside a window whose aspect
/// ratio matches where it will be shown — so「显示的范围」is exactly what they
/// chose. The chosen region is baked into the returned image, so it displays
/// identically everywhere (no server-side crop metadata needed).
///
/// - `aspectRatio`: width / height of the crop window (1 for a circular avatar,
///   the banner ratio for a cover).
/// - `circular`: true masks the window as a circle (avatar preview).
struct ImageCropView: View {
    let image: UIImage
    let aspectRatio: CGFloat
    var circular: Bool = false
    let title: String
    let onCancel: () -> Void
    let onCrop: (UIImage) -> Void

    @Environment(\.appLanguage) private var language

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var resolvedCropSize: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer(minLength: 0)

                GeometryReader { geo in
                    let size = cropSize(in: geo.size)
                    cropArea(cropSize: size)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .task(id: geo.size.width) { resolvedCropSize = size }
                }
                .frame(maxHeight: .infinity)

                hint

                Spacer(minLength: 0)

                actionBar
            }
        }
    }

    // MARK: Layout

    private func cropSize(in container: CGSize) -> CGSize {
        let width = max(0, min(container.width - 40, container.height - 40))
        let cappedWidth = aspectRatio >= 1 ? width : width * aspectRatio
        let w = min(cappedWidth, container.width - 40)
        let h = w / aspectRatio
        if h > container.height - 40 {
            let hh = container.height - 40
            return CGSize(width: hh * aspectRatio, height: hh)
        }
        return CGSize(width: w, height: h)
    }

    // MARK: Crop window

    private func cropArea(cropSize: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: cropSize.width, height: cropSize.height)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: cropSize.width, height: cropSize.height)
            .clipShape(RoundedRectangle(cornerRadius: circular ? cropSize.height / 2 : 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: circular ? cropSize.height / 2 : 18, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
            )
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(cropSize: cropSize))
            .simultaneousGesture(magnifyGesture(cropSize: cropSize))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Gestures

    private func dragGesture(cropSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clampedOffset(
                    CGSize(width: lastOffset.width + value.translation.width,
                           height: lastOffset.height + value.translation.height),
                    cropSize: cropSize
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func magnifyGesture(cropSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 6)
                offset = clampedOffset(offset, cropSize: cropSize)
            }
            .onEnded { _ in
                lastScale = scale
                offset = clampedOffset(offset, cropSize: cropSize)
                lastOffset = offset
            }
    }

    /// Keeps the image covering the whole crop window — the photo can never be
    /// dragged so far that a blank corner shows inside the frame.
    private func clampedOffset(_ proposed: CGSize, cropSize: CGSize) -> CGSize {
        guard cropSize.width > 0, image.size.width > 0, image.size.height > 0 else { return .zero }
        let base = max(cropSize.width / image.size.width, cropSize.height / image.size.height)
        let total = base * scale
        let contentW = image.size.width * total
        let contentH = image.size.height * total
        let maxX = max(0, (contentW - cropSize.width) / 2)
        let maxY = max(0, (contentH - cropSize.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    // MARK: Render

    private func confirm() {
        onCrop(renderCrop(cropSize: resolvedCropSize))
    }

    /// Extracts the pixels currently framed by the crop window from the original
    /// image, at full resolution. Mirrors the on-screen geometry exactly so the
    /// baked result matches the preview.
    private func renderCrop(cropSize: CGSize) -> UIImage {
        guard cropSize.width > 0, cropSize.height > 0 else { return image }
        let normalized = normalizedUp(image)
        let imgSize = normalized.size
        guard imgSize.width > 0, imgSize.height > 0 else { return normalized }

        let base = max(cropSize.width / imgSize.width, cropSize.height / imgSize.height)
        let total = base * scale
        let cropW = cropSize.width / total
        let cropH = cropSize.height / total
        let originX = (imgSize.width - cropW) / 2 - offset.width / total
        let originY = (imgSize.height - cropH) / 2 - offset.height / total

        let px = normalized.scale
        let pixelRect = CGRect(x: originX * px, y: originY * px, width: cropW * px, height: cropH * px)
        let bounds = CGRect(x: 0, y: 0, width: imgSize.width * px, height: imgSize.height * px)
        let clamped = pixelRect.intersection(bounds).integral
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1,
              let cg = normalized.cgImage?.cropping(to: clamped) else {
            return normalized
        }
        return UIImage(cgImage: cg, scale: normalized.scale, orientation: .up)
    }

    /// Redraws an image whose EXIF orientation isn't `.up` so pixel-space
    /// cropping lines up with what SwiftUI displays.
    private func normalizedUp(_ input: UIImage) -> UIImage {
        guard input.imageOrientation != .up else { return input }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = input.scale
        let renderer = UIGraphicsImageRenderer(size: input.size, format: format)
        return renderer.image { _ in input.draw(in: CGRect(origin: .zero, size: input.size)) }
    }

    // MARK: Chrome

    private func resetTransform() {
        withAnimation(.snappy(duration: 0.2)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }

    private var header: some View {
        ZStack {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            HStack {
                Button { onCancel() } label: {
                    Text(L("cancel", language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, KXSpacing.lg)
                        .frame(height: 38)
                        .background(.white.opacity(0.16), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                Button { resetTransform() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.16), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KXListingCopy.pickText(language, "重置", "リセット", "Reset"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var hint: some View {
        Text(KXListingCopy.pickText(
            language,
            "拖动移动位置 · 双指缩放 · 选择要显示的范围",
            "ドラッグで移動・ピンチで拡大・表示範囲を選択",
            "Drag to move · pinch to zoom · choose what shows"
        ))
        .font(.footnote.weight(.medium))
        .foregroundStyle(.white.opacity(0.72))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, KXSpacing.sm)
    }

    private var actionBar: some View {
        Button {
            confirm()
        } label: {
            Text(KXListingCopy.pickText(language, "使用", "使う", "Use photo"))
                .font(.headline.weight(.bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, KXSpacing.md)
        .padding(.bottom, 28)
    }
}
