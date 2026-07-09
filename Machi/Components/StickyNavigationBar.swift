import SwiftUI

struct StickyNavigationBar: View {
    let title: String
    var trailingSystemImage: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.title2.weight(.semibold))
            Spacer()
            if let trailingSystemImage, let trailingAction {
                Button(action: trailingAction) {
                    Image(systemName: trailingSystemImage)
                        .font(.headline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .kxGlassCircle()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.vertical, 10)
        .kxGlassBar()
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }
}
