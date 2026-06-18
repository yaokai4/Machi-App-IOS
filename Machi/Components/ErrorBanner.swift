import SwiftUI

struct ErrorBanner: View {
    @Environment(\.appLanguage) private var language
    let item: ToastItem
    let onDismiss: () -> Void
    @State private var isExpanded = false

    private var shouldShowDebugDetails: Bool {
        #if DEBUG
        item.state.technicalDetails?.isEmpty == false
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .top, spacing: KXSpacing.sm) {
                Image(systemName: item.state.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.state.tint)
                    .frame(width: 28, height: 28)
                    .background(item.state.tint.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.state.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(item.state.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                }

                Spacer(minLength: KXSpacing.sm)

                if let retryTitle = item.state.retryTitle, let retry = item.retry {
                    Button(retryTitle, action: retry)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.state.tint)
                        .buttonStyle(.plain)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("dismissBanner", language))
            }

            if shouldShowDebugDetails {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label(isExpanded ? "隐藏技术细节" : "显示技术细节", systemImage: "curlybraces.square")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if isExpanded, let details = item.state.technicalDetails {
                    Text(details)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(KXSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                }
            }
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg, elevated: true)
        .padding(.horizontal, KXSpacing.screen)
    }
}

struct ToastHost: ViewModifier {
    @ObservedObject var toastManager: ToastManager

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let item = toastManager.current {
                    ErrorBanner(item: item, onDismiss: toastManager.dismiss)
                        .padding(.top, KXSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .animation(.snappy(duration: 0.22), value: toastManager.current?.id)
    }
}

extension View {
    func toastHost(_ toastManager: ToastManager) -> some View {
        modifier(ToastHost(toastManager: toastManager))
    }
}
