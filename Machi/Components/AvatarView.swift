import SwiftUI

struct AvatarView: View {
    let user: UserEntity?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            fallbackAvatar
            if let url = user?.avatarURL.kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: size * 3, failureMode: .transparent)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallbackAvatar: some View {
        if user?.isMachiOfficialAccount == true {
            MachiOfficialAvatarView(size: size)
        } else {
            Circle()
                .fill(Color.kaixNamed(user?.avatarColorName ?? "blue").gradient)
            Text(user?.fallbackAvatarInitial ?? "?")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
    }
}

struct MachiOfficialAvatarView: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.17, green: 0.42, blue: 0.78),
                            Color(red: 0.09, green: 0.62, blue: 0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("M")
                .font(.system(size: size * 0.43, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        // Without this frame the greedy Circle expands to fill its parent —
        // which made official-account avatars render full-width in feed
        // cards (`MachiOfficialAvatarView(size: 38)` used directly, with no
        // outer frame like AvatarView provides).
        .frame(width: size, height: size)
    }
}

extension UserEntity {
    var isMachiOfficialAccount: Bool {
        let handle = username.lowercased()
        let name = displayName.lowercased()
        return handle.hasPrefix("machi_")
            || handle.contains("machi")
            || name.contains("machi 城市助手")
            || name.contains("machi 编辑部")
            || name.contains("machi 东京编辑部")
            || name.contains("machi 日本生活编辑部")
            || name.contains("machi 本地生活编辑部")
            || name.contains("machi local")
            || name.contains("machi assistant")
    }

    var fallbackAvatarInitial: String {
        let preferred = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = preferred.isEmpty ? fallback : preferred
        guard let first = source.first else { return "?" }
        return String(first).uppercased()
    }
}
