import SwiftData
import SwiftUI

struct AccountSwitcherView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var users: [UserEntity] = []
    @State private var state: ScreenState = .idle

    let currentUser: UserEntity
    let onSwitch: (UserEntity) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: KXSpacing.md) {
                switch state {
                case .loading, .idle:
                    LoadingView()
                        .frame(maxWidth: .infinity)
                case .empty:
                    EmptyStateView(title: L("noAccounts", language), subtitle: L("noAccountsSubtitle", language), systemImage: "person.2")
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await load() }
                    }
                case .loaded:
                    ForEach(users) { user in
                        Button {
                            AuthService.shared.switchAccount(to: user)
                            onSwitch(user)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                AvatarView(user: user, size: 54)

                                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                                    HStack(spacing: 5) {
                                        Text(user.displayName)
                                            .font(.headline.weight(.semibold))
                                        KXUserBadge(user: user)
                                    }
                                    Text("@\(user.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if user.id == currentUser.id {
                                    Text(L("current", language))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Capsule())
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.secondary.opacity(0.6))
                                }
                            }
                            .padding(14)
                            .kxGlassSurface(radius: KXRadius.lg)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(KXSpacing.screen)
        }
        .kxPageBackground()
        .navigationTitle(L("switchAccount", language))
        .task { await load() }
    }

    @MainActor
    private func load() async {
        state = .loading
        do {
            // 只列本机 SwiftData 里已登录过的账号(DEBUG 本地夹具流程)。绝不走
            // UserRepository.fetchUsers():那个在生产返回服务端 trending 用户——
            // 把热门陌生人列成"可切换账号"且切换不换 token,等于顶着自己的
            // token 冒充别人的身份展示。生产入口已在设置里 #if DEBUG 移除,
            // 这里再兜底一层。
            if KaiXRuntimeFlags.allowLocalStoreFallback, KaiXBackend.token == nil {
                users = try modelContext.fetch(
                    FetchDescriptor<UserEntity>(sortBy: [SortDescriptor(\.displayName)])
                )
            } else {
                users = []
            }
            state = users.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}
