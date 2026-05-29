import SwiftUI

struct AvatarView: View {
    let user: UserEntity?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            if let url = user?.avatarURL.kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: size * 3)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.kaixNamed(user?.avatarColorName ?? "blue").gradient)
                Image(systemName: user?.avatarSymbol ?? "person.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
