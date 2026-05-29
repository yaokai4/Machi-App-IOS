import SwiftData
import SwiftUI

struct AccountPasswordSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var username: String
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var usernameMessage: String?
    @State private var message: String?
    @State private var isSavingUsername = false
    let user: UserEntity

    init(user: UserEntity) {
        self.user = user
        _username = State(initialValue: user.username)
    }

    var body: some View {
        SettingsFormPage(title: L("accountPassword", language)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("username", language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(L("username", language), text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .controlSize(.large)
                Button {
                    Task { await saveUsername() }
                } label: {
                    if isSavingUsername {
                        ProgressView()
                    } else {
                        Text(L("saveUsername", language))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSaveUsername)

                if !username.normalizedUsername.isEmpty, username.normalizedUsername != username.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Text(L("usernameWillNormalize", language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let usernameMessage {
                    Text(usernameMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            SecureField(L("newPassword", language), text: $newPassword)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .controlSize(.large)
            SecureField(L("confirmPassword", language), text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .controlSize(.large)
            Button(L("savePassword", language)) {
                guard newPassword.count >= 6, newPassword == confirmPassword else {
                    message = L("passwordValidationMessage", language)
                    return
                }
                user.passwordHash = PasswordHasher.hash(newPassword)
                user.updatedAt = .now
                do {
                    try modelContext.save()
                    newPassword = ""
                    confirmPassword = ""
                    message = L("passwordUpdated", language)
                } catch {
                    message = L("databaseSaveFailed", language)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSavePassword)
            if !newPassword.isEmpty || !confirmPassword.isEmpty, !canSavePassword {
                Text(L("passwordValidationMessage", language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var canSavePassword: Bool {
        newPassword.count >= 6 && newPassword == confirmPassword
    }

    private var canSaveUsername: Bool {
        !isSavingUsername
        && !username.normalizedUsername.isEmpty
        && username.normalizedUsername != user.username
    }

    private func saveUsername() async {
        guard canSaveUsername else { return }
        isSavingUsername = true
        defer { isSavingUsername = false }
        do {
            try await UserRepository(context: modelContext).updateUsername(user: user, username: username)
            username = user.username
            usernameMessage = L("usernameUpdated", language)
        } catch RepositoryError.duplicate {
            usernameMessage = L("handleTaken", language)
        } catch RepositoryError.validationFailed {
            usernameMessage = L("usernameValidationMessage", language)
        } catch {
            usernameMessage = error.kaixUserMessage
        }
    }
}

struct ContactSettingsView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("accountEmail") private var email = ""
    @AppStorage("accountPhone") private var phone = ""

    var body: some View {
        SettingsFormPage(title: L("contactInfo", language)) {
            TextField(L("email", language), text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .controlSize(.large)
            TextField(L("phone", language), text: $phone)
                .keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .controlSize(.large)
            Text(L("contactStored", language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct MembershipSettingsView: View {
    @Environment(\.appLanguage) private var language
    @State private var message: String?
    let user: UserEntity

    var body: some View {
        SettingsFormPage(title: L("membership", language)) {
            Label(user.isVerified ? L("verifiedAccount", language) : L("notVerified", language), systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(user.isVerified ? .blue : .secondary)
            Text(user.role == .member ? L("memberVerificationHelp", language) : L("creatorAccountHelp", language))
                .foregroundStyle(.secondary)
            Button(L("applyVerification", language)) {
                message = user.isVerified ? L("alreadyVerifiedMessage", language) : L("verificationSaved", language)
            }
                .buttonStyle(.borderedProminent)
                .disabled(user.isVerified)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct BookmarkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @StateObject private var viewModel = SavedContentViewModel()
    let currentUser: UserEntity

    var body: some View {
        ManagedPostListView(
            title: L("bookmarks", language),
            emptySubtitle: L("bookmarkEmptyHelp", language),
            state: viewModel.state,
            posts: viewModel.posts,
            mediaByPostId: viewModel.mediaByPostId,
            authors: viewModel.authors,
            currentUser: currentUser,
            reload: { await viewModel.loadBookmarks(context: modelContext, postStore: postStore) },
            onLike: { post in
                await viewModel.toggleLike(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                    await viewModel.loadBookmarks(context: modelContext, postStore: postStore)
                }
            },
            onBookmark: { post in
                await viewModel.toggleBookmark(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                    await viewModel.loadBookmarks(context: modelContext, postStore: postStore)
                }
            },
            onRepost: { post in
                await viewModel.repost(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                    await viewModel.loadBookmarks(context: modelContext, postStore: postStore)
                }
            },
            onQuoteRepost: { post, content in
                await viewModel.quoteRepost(context: modelContext, post: post, currentUser: currentUser, content: content, postStore: postStore) {
                    await viewModel.loadBookmarks(context: modelContext, postStore: postStore)
                }
            }
        )
        .task { await viewModel.loadBookmarks(context: modelContext, postStore: postStore) }
    }
}

struct MediaLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @StateObject private var viewModel = SavedContentViewModel()
    @State private var filter = MediaLibraryFilter.all
    let currentUser: UserEntity

    private var filteredPosts: [PostEntity] {
        switch filter {
        case .all:
            viewModel.posts
        case .images:
            viewModel.posts.filter { post in
                viewModel.mediaByPostId[post.id]?.contains { $0.type == .image } == true
            }
        case .videos:
            viewModel.posts.filter { post in
                viewModel.mediaByPostId[post.id]?.contains { $0.type == .video } == true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $filter) {
                ForEach(MediaLibraryFilter.allCases) { item in
                    Text(item.title(language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 10)

            ManagedPostListView(
                title: L("mediaLibrary", language),
                emptySubtitle: L("mediaEmptyHelp", language),
                state: viewModel.state,
                posts: filteredPosts,
                mediaByPostId: viewModel.mediaByPostId,
                authors: viewModel.authors,
                currentUser: currentUser,
                reload: { await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore) },
                onLike: { post in
                    await viewModel.toggleLike(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                        await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore)
                    }
                },
                onBookmark: { post in
                    await viewModel.toggleBookmark(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                        await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore)
                    }
                },
                onRepost: { post in
                    await viewModel.repost(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                        await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore)
                    }
                },
                onQuoteRepost: { post, content in
                    await viewModel.quoteRepost(context: modelContext, post: post, currentUser: currentUser, content: content, postStore: postStore) {
                        await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore)
                    }
                }
            )
        }
        .kxPageBackground()
        .navigationTitle(L("mediaLibrary", language))
        .task { await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore) }
    }
}

struct DraftsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @StateObject private var viewModel = DraftsViewModel()
    @State private var selectedDraft: PostEntity?
    let currentUser: UserEntity

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                switch viewModel.state {
                case .loading, .idle:
                    LoadingView()
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await viewModel.load(context: modelContext, currentUser: currentUser) }
                    }
                case .empty:
                    EmptyStateView(title: L("draftsEmpty", language), subtitle: L("draftsHelp", language), systemImage: "tray")
                        .padding(.top, 34)
                case .loaded:
                    ForEach(viewModel.drafts) { draft in
                        DraftCard(
                            draft: draft,
                            mediaItems: viewModel.mediaByPostId[draft.id] ?? [],
                            currentUser: currentUser,
                            edit: { selectedDraft = draft },
                            publish: { Task { await viewModel.publish(context: modelContext, draft: draft, currentUser: currentUser) } },
                            delete: { Task { await viewModel.delete(context: modelContext, draft: draft, currentUser: currentUser) } }
                        )
                    }
                }
            }
            .padding(KaiXTheme.horizontalPadding)
        }
        .kxPageBackground()
        .navigationTitle(L("drafts", language))
        .task { await viewModel.load(context: modelContext, currentUser: currentUser) }
        .sheet(item: $selectedDraft) { draft in
            DraftEditorView(draft: draft, mediaItems: viewModel.mediaByPostId[draft.id] ?? [], currentUser: currentUser) {
                Task { await viewModel.load(context: modelContext, currentUser: currentUser) }
            }
        }
    }
}

private enum MediaLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case images
    case videos

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .all: L("all", language)
        case .images: L("images", language)
        case .videos: L("videos", language)
        }
    }
}

private struct ManagedPostListView: View {
    @EnvironmentObject private var postStore: PostStore
    @State private var selectedDestination: ManagedPostDestination?
    let title: String
    let emptySubtitle: String
    let state: ScreenState
    let posts: [PostEntity]
    let mediaByPostId: [String: [MediaEntity]]
    let authors: [String: UserEntity]
    let currentUser: UserEntity
    let reload: () async -> Void
    let onLike: (PostEntity) async -> Void
    let onBookmark: (PostEntity) async -> Void
    let onRepost: (PostEntity) async -> Void
    let onQuoteRepost: (PostEntity, String) async -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                switch state {
                case .loading, .idle:
                    LoadingView()
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await reload() }
                    }
                case .empty:
                    EmptyStateView(title: title, subtitle: emptySubtitle, systemImage: "tray")
                        .padding(.top, 34)
                case .loaded:
                    if posts.isEmpty {
                        EmptyStateView(title: title, subtitle: emptySubtitle, systemImage: "tray")
                            .padding(.top, 34)
                    } else {
                        ForEach(posts) { post in
                            let displayedPost = postStore.post(id: post.id) ?? post
                            PostCardView(
                                post: displayedPost,
                                author: authors[displayedPost.authorId] ?? currentUser,
                                mediaItems: mediaByPostId[displayedPost.id] ?? [],
                                currentUser: currentUser,
                                onOpen: { selectedDestination = .post(postId: displayedPost.id, focusComments: false) },
                                onAuthor: { selectedDestination = .profile(userId: displayedPost.authorId) },
                                onTag: { selectedDestination = .topic(tag: $0) },
                                onComment: { selectedDestination = .post(postId: displayedPost.id, focusComments: true) },
                                onLike: { Task { await onLike(displayedPost) } },
                                onBookmark: { Task { await onBookmark(displayedPost) } },
                                onRepost: { Task { await onRepost(displayedPost) } },
                                onQuoteRepost: { content in Task { await onQuoteRepost(displayedPost, content) } }
                            )
                            .equatable()
                        }
                    }
                }
            }
            .padding(KaiXTheme.horizontalPadding)
            .padding(.bottom, 24)
        }
        .kxPageBackground()
        .navigationTitle(title)
        .navigationDestination(item: $selectedDestination) { destination in
            switch destination {
            case .post(let postId, let focusComments):
                KXRoutedPostDetailView(
                    postId: postId,
                    currentUser: currentUser,
                    initialFocus: focusComments ? .comments : .none
                )
            case .profile(let userId):
                ManagedProfileRouteView(userId: userId, currentUser: currentUser)
            case .topic(let tag):
                ManagedTopicRouteView(tag: tag, currentUser: currentUser)
            }
        }
    }
}

private enum ManagedPostDestination: Identifiable, Hashable {
    case post(postId: String, focusComments: Bool)
    case profile(userId: String)
    case topic(tag: String)

    var id: String {
        switch self {
        case .post(let postId, let focusComments):
            "post:\(postId):\(focusComments)"
        case .profile(let userId):
            "profile:\(userId)"
        case .topic(let tag):
            "topic:\(tag.normalizedTopicName)"
        }
    }
}

private struct ManagedProfileRouteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var user: UserEntity?
    @State private var state: ScreenState = .idle

    let userId: String
    let currentUser: UserEntity

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                LoadingView()
            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await load() }
                }
            case .empty:
                EmptyStateView(title: L("unknownUser", language), subtitle: L("noContent", language), systemImage: "person.crop.circle")
            case .loaded:
                ProfileView(currentUser: currentUser, profileUserId: userId, profileUser: user, tracksChrome: false, showsBackButton: true)
            }
        }
        .task(id: userId) {
            await load()
        }
    }

    private func load() async {
        state = .loading
        do {
            user = userId == currentUser.id ? currentUser : try await UserRepository(context: modelContext).fetchUser(id: userId)
            state = user == nil ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}

private struct ManagedTopicRouteView: View {
    let tag: String
    let currentUser: UserEntity

    var body: some View {
        TopicDetailView(tag: tag, currentUser: currentUser)
    }
}

private struct DraftCard: View {
    @Environment(\.appLanguage) private var language
    let draft: PostEntity
    let mediaItems: [MediaEntity]
    let currentUser: UserEntity
    let edit: () -> Void
    let publish: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AvatarView(user: currentUser, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("drafts", language))
                        .font(.headline.weight(.semibold))
                    Text(DateFormatterUtils.relativeText(from: draft.updatedAt, language: language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(draft.previewText.isEmpty ? L("placeholderPost", language) : draft.previewText)
                .font(.body)
                .foregroundStyle(draft.previewText.isEmpty ? .secondary : .primary)
                .lineLimit(4)

            MediaGridView(mediaItems: mediaItems)

            HStack {
                Button(L("continueEdit", language), action: edit)
                    .buttonStyle(.bordered)
                Spacer()
                Button(L("deleteDraft", language), role: .destructive, action: delete)
                    .buttonStyle(.bordered)
                Button(L("publishDraft", language), action: publish)
                    .buttonStyle(.borderedProminent)
            }
            .font(.subheadline.weight(.bold))
        }
        .padding(16)
        .kxGlassSurface(radius: KaiXTheme.cardRadius)
    }
}

private struct DraftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var content: String
    @State private var errorMessage: String?
    let draft: PostEntity
    let mediaItems: [MediaEntity]
    let currentUser: UserEntity
    let onDone: () -> Void

    init(draft: PostEntity, mediaItems: [MediaEntity], currentUser: UserEntity, onDone: @escaping () -> Void) {
        self.draft = draft
        self.mediaItems = mediaItems
        self.currentUser = currentUser
        self.onDone = onDone
        _content = State(initialValue: draft.content)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $content)
                    .font(.title3)
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .frame(minHeight: 220)
                    .kxGlassSurface(radius: KXRadius.lg)
                    .padding(KaiXTheme.horizontalPadding)
                    .padding(.top, 14)

                if !mediaItems.isEmpty {
                    MediaGridView(mediaItems: mediaItems)
                        .padding(KaiXTheme.horizontalPadding)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, KaiXTheme.horizontalPadding)
                }

                Spacer()
            }
            .kxPageBackground()
            .navigationTitle(L("continueEdit", language))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("cancel", language)) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("publish", language)) {
                        Task { await publish() }
                    }
                    .fontWeight(.black)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaItems.isEmpty)
                }
            }
        }
    }

    private func publish() async {
        do {
            let repository = PostRepository(context: modelContext)
            try await repository.updateDraft(post: draft, content: content)
            try await repository.publishDraft(post: draft)
            onDone()
            dismiss()
        } catch {
            errorMessage = error.kaixUserMessage
        }
    }
}

struct AppearanceSettingsView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some View {
        SettingsFormPage(title: L("appearance", language)) {
            ForEach(AppAppearance.allCases) { appearance in
                Button {
                    appAppearance = appearance.rawValue
                } label: {
                    HStack {
                        Text(appearance.title(language))
                        Spacer()
                        if appAppearance == appearance.rawValue {
                            Image(systemName: "checkmark")
                                .fontWeight(.black)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}

struct NotificationPreferencesView: View {
    @Environment(\.appLanguage) private var language
    @State private var notifyLikes = true
    @State private var notifyComments = true
    @State private var notifyReposts = true
    @State private var notifyFollows = true
    @State private var notifyMessages = true
    @State private var notifySystem = true
    let currentUser: UserEntity

    var body: some View {
        SettingsFormPage(title: L("notificationSettings", language)) {
            Toggle(L("likeNotifications", language), isOn: preferenceBinding(.like, $notifyLikes))
            Toggle(L("commentNotifications", language), isOn: preferenceBinding(.comment, $notifyComments))
            Toggle(L("repostNotifications", language), isOn: preferenceBinding(.repost, $notifyReposts))
            Toggle(L("followNotifications", language), isOn: preferenceBinding(.follow, $notifyFollows))
            Toggle(L("messageNotifications", language), isOn: messagePreferenceBinding)
            Toggle(L("systemNotifications", language), isOn: preferenceBinding(.system, $notifySystem))
        }
        .onAppear {
            notifyLikes = NotificationPreferenceService.isEnabled(.like, recipientUserId: currentUser.id)
            notifyComments = NotificationPreferenceService.isEnabled(.comment, recipientUserId: currentUser.id)
            notifyReposts = NotificationPreferenceService.isEnabled(.repost, recipientUserId: currentUser.id)
            notifyFollows = NotificationPreferenceService.isEnabled(.follow, recipientUserId: currentUser.id)
            notifySystem = NotificationPreferenceService.isEnabled(.system, recipientUserId: currentUser.id)
            notifyMessages = UserDefaults.standard.object(forKey: messagePreferenceKey) as? Bool ?? true
        }
    }

    private func preferenceBinding(_ type: NotificationType, _ state: Binding<Bool>) -> Binding<Bool> {
        Binding {
            state.wrappedValue
        } set: { value in
            state.wrappedValue = value
            NotificationPreferenceService.setEnabled(value, type: type, recipientUserId: currentUser.id)
        }
    }

    private var messagePreferenceKey: String {
        "notification.\(currentUser.id).message"
    }

    private var messagePreferenceBinding: Binding<Bool> {
        Binding {
            notifyMessages
        } set: { value in
            notifyMessages = value
            UserDefaults.standard.set(value, forKey: messagePreferenceKey)
        }
    }
}

struct PrivacySettingsView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("profileVisibility") private var profileVisibility = "public"
    @AppStorage("allowMessageFromStrangers") private var allowMessageFromStrangers = true

    var body: some View {
        SettingsFormPage(title: L("privacySettings", language)) {
            Picker(L("profileVisibility", language), selection: $profileVisibility) {
                Text(L("public", language)).tag("public")
                Text(L("followersOnly", language)).tag("followers")
                Text(L("onlyMe", language)).tag("private")
            }
            .pickerStyle(.segmented)
            Toggle(L("allowStrangerMessages", language), isOn: $allowMessageFromStrangers)
        }
    }
}

struct RecommendationSettingsView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("recommendLocalLife") private var recommendLocalLife = true
    @AppStorage("recommendNews") private var recommendNews = true
    @AppStorage("recommendTech") private var recommendTech = false

    var body: some View {
        SettingsFormPage(title: L("recommendationSettings", language)) {
            Toggle(L("recommendLocalLife", language), isOn: $recommendLocalLife)
            Toggle(L("recommendNews", language), isOn: $recommendNews)
            Toggle(L("recommendTech", language), isOn: $recommendTech)
        }
    }
}

struct LoginDevicesView: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        SettingsFormPage(title: L("loginDevices", language)) {
            Label(L("currentDevice", language), systemImage: "iphone")
                .font(.headline.weight(.bold))
            Text(L("lastActiveNow", language))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct BlocklistSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @AppStorage("blockedUserIds") private var blockedUserIdsRaw = ""
    @State private var blockedUsers: [UserEntity] = []
    @State private var errorMessage: String?

    var body: some View {
        SettingsFormPage(title: L("blocklist", language)) {
            if blockedUserIds.isEmpty {
                Text(L("noBlockedUsers", language))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(blockedUserIds, id: \.self) { userId in
                        blockedUserRow(userId: userId)
                        if userId != blockedUserIds.last {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                        .stroke(KXColor.separator, lineWidth: 0.6)
                }
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    Label(errorMessage, systemImage: "xmark.octagon.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                    Button(L("retry", language)) {
                        Task { await loadBlockedUsers() }
                    }
                    .font(.footnote.weight(.semibold))
                }
                .padding(KXSpacing.md)
                .kxGlassSurface(radius: KXRadius.md)
            }
        }
        .task { await loadBlockedUsers() }
        .onChange(of: blockedUserIdsRaw) {
            Task { await loadBlockedUsers() }
        }
    }

    private var blockedUserIds: [String] {
        blockedUserIdsRaw
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty }
            .removingDuplicates()
    }

    private func blockedUserRow(userId: String) -> some View {
        let user = blockedUsers.first { $0.id == userId }

        return HStack(spacing: KXSpacing.md) {
            AvatarView(user: user, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(user?.displayName ?? L("unknownUser", language))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(user.map { "@\($0.username)" } ?? userId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(L("unblockUser", language)) {
                unblock(userId)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, 10)
    }

    private func loadBlockedUsers() async {
        guard !blockedUserIds.isEmpty else {
            blockedUsers = []
            errorMessage = nil
            return
        }
        do {
            blockedUsers = try await UserRepository(context: modelContext).fetchUsers(ids: Set(blockedUserIds))
            errorMessage = nil
        } catch {
            errorMessage = error.kaixUserMessage
        }
    }

    private func unblock(_ userId: String) {
        blockedUserIdsRaw = blockedUserIds
            .filter { $0 != userId }
            .joined(separator: "|")
    }
}

struct DataExportView: View {
    @Environment(\.appLanguage) private var language
    @State private var exported = false
    let postCount: Int
    let likeCount: Int
    let bookmarkCount: Int

    var body: some View {
        SettingsFormPage(title: L("dataExport", language)) {
            Text(L("localDataSummary", language))
                .font(.headline.weight(.semibold))
            Text("\(L("posts", language)) \(postCount) · \(L("likes", language)) \(likeCount) · \(L("bookmarks", language)) \(bookmarkCount)")
                .foregroundStyle(.secondary)
            Button(L("generateExport", language)) {
                exported = true
            }
                .buttonStyle(.borderedProminent)
            if exported {
                Text(L("exportSummaryGenerated", language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CacheSettingsView: View {
    @Environment(\.appLanguage) private var language
    @State private var showConfirm = false
    @State private var message: String?

    var body: some View {
        SettingsFormPage(title: L("clearCache", language)) {
            Text(L("cacheDescription", language))
                .foregroundStyle(.secondary)
            Button(L("clearCache", language), role: .destructive) {
                showConfirm = true
            }
            .buttonStyle(.borderedProminent)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(L("clearCacheConfirm", language), isPresented: $showConfirm, titleVisibility: .visible) {
            Button(L("clearCache", language), role: .destructive) {
                Task {
                    URLCache.shared.removeAllCachedResponses()
                    await ImageCacheService.shared.clear()
                    await VideoThumbnailService.shared.clear()
                    message = L("cacheCleared", language)
                }
            }
            Button(L("cancel", language), role: .cancel) {}
        }
    }
}

struct HelpCenterView: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        SettingsFormPage(title: L("helpCenter", language)) {
            Text(L("faq", language))
                .font(.headline.weight(.semibold))
            Text(L("helpPublishMedia", language))
                .foregroundStyle(.secondary)
            Text(L("helpLocalData", language))
                .foregroundStyle(.secondary)
        }
    }
}

struct FeedbackView: View {
    @Environment(\.appLanguage) private var language
    @State private var text = ""
    @State private var submitted = false

    var body: some View {
        SettingsFormPage(title: L("feedback", language)) {
            TextField(L("feedbackPlaceholder", language), text: $text, axis: .vertical)
                .lineLimit(5...8)
                .textFieldStyle(.roundedBorder)
            Button(L("submitFeedback", language)) {
                submitted = true
                text = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if submitted {
                Text(L("feedbackSaved", language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AboutKaiXView: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        SettingsFormPage(title: L("aboutKaiX", language)) {
            Text("Machi")
                .font(.system(size: 38, weight: .black, design: .rounded))
            Text(L("aboutSubtitle", language))
                .foregroundStyle(.secondary)
            Text("\(L("version", language)) 1.0.0")
                .font(.footnote.weight(.bold))
        }
    }
}

struct DeveloperInfoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var counts: [(String, String)] = []
    let currentUser: UserEntity

    var body: some View {
        SettingsFormPage(title: L("developerInfo", language)) {
            Text(L("architecture", language))
                .font(.headline.weight(.semibold))
            Text("MVVM + Repository + SwiftData + Services")
                .foregroundStyle(.secondary)
            Text(L("developerArchitectureText", language))
                .foregroundStyle(.secondary)

            Divider()

            Text(L("databaseStatus", language))
                .font(.headline.weight(.semibold))
            ForEach(counts, id: \.0) { item in
                HStack {
                    Text(item.0)
                    Spacer()
                    Text(item.1)
                        .fontWeight(.bold)
                }
                .font(.subheadline)
            }
        }
        .task { loadCounts() }
    }

    private func loadCounts() {
        let users = (try? modelContext.fetch(FetchDescriptor<UserEntity>()).count) ?? 0
        let posts = (try? modelContext.fetch(FetchDescriptor<PostEntity>()).count) ?? 0
        let comments = (try? modelContext.fetch(FetchDescriptor<CommentEntity>()).count) ?? 0
        let notifications = (try? modelContext.fetch(FetchDescriptor<NotificationEntity>()).count) ?? 0
        let threads = (try? modelContext.fetch(FetchDescriptor<MessageThreadEntity>()).count) ?? 0
        counts = [
            (L("currentUserId", language), currentUser.id),
            (L("databaseStatus", language), L("online", language)),
            (L("userCount", language), "\(users)"),
            (L("postCount", language), "\(posts)"),
            (L("commentCount", language), "\(comments)"),
            (L("notificationCount", language), "\(notifications)"),
            (L("threadCount", language), "\(threads)")
        ]
    }
}

struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var confirmText = ""
    @State private var showFinalConfirm = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    let currentUser: UserEntity
    let onDeleted: () -> Void

    var body: some View {
        SettingsFormPage(title: L("deleteAccount", language)) {
            Text(L("deleteAccountDescription", language))
                .foregroundStyle(.secondary)
            TextField(L("enterDelete", language), text: $confirmText)
                .textInputAutocapitalization(.characters)
                .textFieldStyle(.roundedBorder)
            Button(L("deleteAccount", language), role: .destructive) {
                showFinalConfirm = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(confirmText != "DELETE" || isDeleting)
            if isDeleting {
                ProgressView()
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog(L("secondDeleteConfirm", language), isPresented: $showFinalConfirm, titleVisibility: .visible) {
            Button(L("confirmDelete", language), role: .destructive) {
                Task { await deleteAccount() }
            }
            Button(L("cancel", language), role: .cancel) {}
        }
    }

    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await UserRepository(context: modelContext).deleteAccount(user: currentUser)
            AuthService.shared.logout()
            onDeleted()
            dismiss()
        } catch {
            errorMessage = L("databaseSaveFailed", language)
        }
    }
}

struct SettingsFormPage<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .font(.body)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxGlassSurface(radius: KXRadius.sheet)
            .padding(KaiXTheme.horizontalPadding)
            .padding(.top, KXSpacing.sm)
            .padding(.bottom, 34)
        }
        .kxPageBackground()
        .navigationTitle(title)
    }
}
