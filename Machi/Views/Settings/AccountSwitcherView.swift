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
            LazyVStack(alignment: .leading, spacing: 12) {
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

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 5) {
                                        Text(user.displayName)
                                            .font(.headline.weight(.semibold))
                                        if user.displaysVerifiedBadge {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundStyle(.blue)
                                        }
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
            .padding(KaiXTheme.horizontalPadding)
        }
        .kxPageBackground()
        .navigationTitle(L("switchAccount", language))
        .task { await load() }
    }

    @MainActor
    private func load() async {
        state = .loading
        do {
            users = try await UserRepository(context: modelContext).fetchUsers()
            state = users.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}
