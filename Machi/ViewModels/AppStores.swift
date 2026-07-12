import Combine
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var currentUserId: String?
    @Published private(set) var isSessionValid = true

    func setCurrentUser(_ userId: String?) {
        currentUserId = userId
        isSessionValid = userId != nil
    }

    func invalidate() {
        currentUserId = nil
        isSessionValid = false
    }
}

@MainActor
final class UserStore: ObservableObject {
    @Published private(set) var usersById: [String: UserEntity] = [:]
    @Published private(set) var currentUserId: String?
    @Published private(set) var profileIds: [String] = []
    @Published private(set) var followStateByUserId: [String: Bool] = [:]
    @Published private(set) var followerCounts: [String: Int] = [:]
    @Published private(set) var followingCounts: [String: Int] = [:]

    func setCurrentUser(_ user: UserEntity?) {
        currentUserId = user?.id
        if let user {
            register(user)
        }
    }

    func register(_ user: UserEntity) {
        usersById[user.id] = user
        followerCounts[user.id] = user.followerCount
        followingCounts[user.id] = user.followingCount
        if !profileIds.contains(user.id) {
            profileIds.append(user.id)
        }
    }

    func register(_ users: [UserEntity]) {
        users.forEach(register)
    }

    func setFollowing(_ isFollowing: Bool, userId: String) {
        followStateByUserId[userId] = isFollowing
    }

    func updateCounts(userId: String, followers: Int, following: Int) {
        followerCounts[userId] = followers
        followingCounts[userId] = following
        usersById[userId]?.followerCount = followers
        usersById[userId]?.followingCount = following
    }
}

@MainActor
final class CommentStore: ObservableObject {
    @Published private(set) var commentsByPostId: [String: [CommentEntity]] = [:]
    @Published private(set) var commentCountsByPostId: [String: Int] = [:]
    @Published private(set) var loadingStateByPostId: [String: CommentLoadState] = [:]
    @Published var focusedCommentId: String?
    @Published var replyDrafts: [String: String] = [:]

    func setComments(_ comments: [CommentEntity], postId: String, expectedCount: Int) {
        commentsByPostId[postId] = comments
        commentCountsByPostId[postId] = expectedCount
        loadingStateByPostId[postId] = CommentLoadState.resolved(commentCount: expectedCount, loadedComments: comments)
    }

    func setLoadingState(_ state: CommentLoadState, postId: String) {
        loadingStateByPostId[postId] = state
    }

    func insertOptimistic(_ comment: CommentEntity) {
        commentsByPostId[comment.postId, default: []].insert(comment, at: 0)
        commentCountsByPostId[comment.postId, default: 0] += 1
        loadingStateByPostId[comment.postId] = .loaded
    }

    func replaceComment(id: String, with comment: CommentEntity) {
        guard var comments = commentsByPostId[comment.postId],
              let index = comments.firstIndex(where: { $0.id == id }) else { return }
        comments[index] = comment
        commentsByPostId[comment.postId] = comments
    }

    func removeComment(_ comment: CommentEntity) {
        let removedCount = commentsByPostId[comment.postId]?.filter { $0.id == comment.id || $0.parentCommentId == comment.id }.count ?? 1
        commentsByPostId[comment.postId]?.removeAll { $0.id == comment.id || $0.parentCommentId == comment.id }
        commentCountsByPostId[comment.postId] = max(0, (commentCountsByPostId[comment.postId] ?? 0) - removedCount)
        loadingStateByPostId[comment.postId] = CommentLoadState.resolved(
            commentCount: commentCountsByPostId[comment.postId] ?? 0,
            loadedComments: commentsByPostId[comment.postId] ?? []
        )
    }

    func updateCount(postId: String, delta: Int) {
        commentCountsByPostId[postId] = max(0, (commentCountsByPostId[postId] ?? 0) + delta)
        loadingStateByPostId[postId] = CommentLoadState.resolved(
            commentCount: commentCountsByPostId[postId] ?? 0,
            loadedComments: commentsByPostId[postId] ?? []
        )
    }

    /// Drop every cached comment thread + reply draft on logout / account
    /// switch so drafts and comments never bleed across accounts.
    func reset() {
        commentsByPostId = [:]
        commentCountsByPostId = [:]
        loadingStateByPostId = [:]
        focusedCommentId = nil
        replyDrafts = [:]
    }
}

@MainActor
final class NotificationStore: ObservableObject {
    @Published private(set) var notificationsById: [String: NotificationEntity] = [:]
    @Published private(set) var groupedNotificationIds: [[String]] = []
    @Published private(set) var unreadCount = 0
    @Published var filterState: String = "all"
    @Published private(set) var loadingState: ScreenState = .idle

    /// Unread count for social notifications only (likes, comments, follows…).
    /// DM-backed types (`.message` / `.listingInquiry`) are excluded: each of
    /// those rows mirrors a conversation MessageStore already counts per-thread,
    /// so adding them into the app-icon badge would double-count every unread
    /// DM (and contradict the messages tab badge).
    var socialUnreadCount: Int {
        // Count unread GROUPS (one per aggregated card the notifications list
        // renders), not raw rows — so a badge of "3" opens to exactly 3 unread
        // cards instead of, say, one "X and 4 others liked your post" card. Reuses
        // the same groupedNotificationIds the list is built from. DM-backed types
        // stay excluded: MessageStore already counts those per-thread.
        groupedNotificationIds.reduce(into: 0) { count, ids in
            guard let type = ids.first.flatMap({ notificationsById[$0]?.type }),
                  type != .message, type != .listingInquiry else { return }
            if ids.contains(where: { notificationsById[$0]?.isRead == false }) {
                count += 1
            }
        }
    }

    func setNotifications(_ notifications: [NotificationEntity]) {
        notificationsById = Dictionary(uniqueKeysWithValues: notifications.map { ($0.id, $0) })
        groupedNotificationIds = Dictionary(grouping: notifications, by: AggregatedNotification.groupKey(for:))
            .values
            .map { $0.sorted { $0.createdAt > $1.createdAt }.map(\.id) }
            .sorted {
                let lhsDate = $0.first.flatMap { notificationsById[$0]?.createdAt } ?? .distantPast
                let rhsDate = $1.first.flatMap { notificationsById[$0]?.createdAt } ?? .distantPast
                return lhsDate > rhsDate
            }
        unreadCount = notifications.filter { !$0.isRead }.count
    }

    func setUnreadCount(_ count: Int) {
        let next = max(0, count)
        guard unreadCount != next else { return }
        unreadCount = next
    }

    func setLoadingState(_ state: ScreenState) {
        loadingState = state
    }

    /// Wipe all notification state so a logout / account switch never leaks the
    /// previous account's notifications (and its unread badge) into the next.
    func reset() {
        notificationsById = [:]
        groupedNotificationIds = []
        unreadCount = 0
        filterState = "all"
        loadingState = .idle
    }
}

@MainActor
final class MessageStore: ObservableObject {
    @Published private(set) var conversationsById: [String: MessageThreadEntity] = [:]
    @Published private(set) var messagesByConversationId: [String: [MessageEntity]] = [:]
    @Published private(set) var unreadCounts: [String: Int] = [:]
    @Published private(set) var sendingQueue: [MessageEntity] = []
    @Published private(set) var uploadQueue: [MediaDraft] = []

    var totalUnreadCount: Int {
        unreadCounts.values.reduce(0) { $0 + max(0, $1) }
    }

    func setConversations(_ conversations: [MessageThreadEntity]) {
        conversationsById = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        unreadCounts = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0.unreadCount) })
    }

    func upsertConversation(_ conversation: MessageThreadEntity) {
        conversationsById[conversation.id] = conversation
        unreadCounts[conversation.id] = max(0, conversation.unreadCount)
    }

    func setMessages(_ messages: [MessageEntity], conversationId: String) {
        messagesByConversationId[conversationId] = messages
        sendingQueue.removeAll { $0.threadId == conversationId && $0.status == .sent }
    }

    func removeConversation(_ conversationId: String) {
        conversationsById.removeValue(forKey: conversationId)
        messagesByConversationId.removeValue(forKey: conversationId)
        unreadCounts.removeValue(forKey: conversationId)
        sendingQueue.removeAll { $0.threadId == conversationId }
    }

    func enqueueSending(_ message: MessageEntity) {
        sendingQueue.append(message)
    }

    func removeFromQueue(_ messageId: String) {
        sendingQueue.removeAll { $0.id == messageId }
    }

    func setUnreadCount(_ count: Int, conversationId: String) {
        unreadCounts[conversationId] = max(0, count)
        conversationsById[conversationId]?.unreadCount = max(0, count)
    }

    func enqueueUpload(_ draft: MediaDraft) {
        uploadQueue.append(draft)
    }

    func removeUpload(_ draftId: String) {
        uploadQueue.removeAll { $0.id == draftId }
    }

    /// Wipe every conversation, message, unread count and pending queue so the
    /// next account never sees the previous account's DMs or unread badge.
    func reset() {
        conversationsById = [:]
        messagesByConversationId = [:]
        unreadCounts = [:]
        sendingQueue = []
        uploadQueue = []
    }
}

@MainActor
final class SearchStore: ObservableObject {
    @Published var query = ""
    @Published private(set) var recentSearches: [String] = []
    @Published private(set) var trendingIds: [String] = []
    @Published private(set) var trendingById: [String: TrendingItem] = [:]
    @Published private(set) var postResultIds: [String] = []
    @Published private(set) var userResultIds: [String] = []
    @Published private(set) var topicResultIds: [String] = []
    @Published private(set) var loadingState: ScreenState = .idle

    func setRecentSearches(_ items: [String]) {
        recentSearches = Array(items.prefix(12))
    }

    func setTrending(_ items: [TrendingItem]) {
        trendingById.merge(Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })) { _, new in new }
        trendingIds = items.map(\.id)
    }

    func setResults(_ items: [TrendingItem]) {
        trendingById.merge(Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })) { _, new in new }
        postResultIds = items.compactMap(\.postId)
        userResultIds = items.compactMap(\.userId)
        topicResultIds = items.compactMap(\.topicId)
    }

    func setLoadingState(_ state: ScreenState) {
        loadingState = state
    }

    /// Clear the search query, recent history, trending cache and results so a
    /// logout / account switch starts search from a clean slate.
    func reset() {
        query = ""
        recentSearches = []
        trendingIds = []
        trendingById = [:]
        postResultIds = []
        userResultIds = []
        topicResultIds = []
        loadingState = .idle
    }
}

@MainActor
final class ComposeStore: ObservableObject {
    @Published var currentDraft: String = ""
    @Published var selectedMedia: [MediaDraft] = []
    @Published var selectedTags: [String] = []
    @Published var uploadProgress: [String: Double] = [:]
    @Published var publishState: ScreenState = .idle
    /// Set by leaf views (e.g. channel empty states) when they want
    /// the global composer to open with a specific ContentType
    /// pre-selected. MainTabView observes this and re-presents its
    /// fullScreenCover. Cleared back to nil when the composer
    /// actually opens so subsequent requests don't double-fire.
    @Published var pendingComposeContentType: ContentType?

    func setDraft(content: String, media: [MediaDraft], tags: [String]) {
        currentDraft = content
        selectedMedia = media
        selectedTags = tags.normalizedDisplayHashtags
    }

    /// Ask the host to open the global composer with `type` pre-selected.
    /// Leaf views call this instead of holding their own binding to
    /// the cover state.
    func requestCompose(_ type: ContentType) {
        pendingComposeContentType = type
    }

    func clear() {
        currentDraft = ""
        selectedMedia = []
        selectedTags = []
        uploadProgress = [:]
        publishState = .idle
        pendingComposeContentType = nil
    }
}
