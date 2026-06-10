import Foundation
import SwiftData
import Testing
@testable import Machi

@MainActor
struct kaiziTests {
    @Test func commentStateDoesNotShowEmptyWhenCountIsPositive() async throws {
        let state = CommentLoadState.resolved(commentCount: 3, loadedComments: [])

        #expect(state != .empty)
        if case .failed = state {
            return
        } else {
            Issue.record("Positive commentCount with an empty array must show retry/loading, not empty.")
        }
    }

    @Test func commentRepositoryDefaultsToHotThenNewestOrdering() async throws {
        let context = try makeContext()
        let oldHot = CommentEntity(
            id: "comment-old-hot",
            postId: "post-comments-order",
            authorId: "author",
            content: "Old hot",
            likeCount: 3,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let newHot = CommentEntity(
            id: "comment-new-hot",
            postId: "post-comments-order",
            authorId: "author",
            content: "New hot",
            likeCount: 3,
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let newestCold = CommentEntity(
            id: "comment-new-cold",
            postId: "post-comments-order",
            authorId: "author",
            content: "Newest cold",
            likeCount: 1,
            createdAt: Date(timeIntervalSince1970: 30)
        )
        context.insert(oldHot)
        context.insert(newHot)
        context.insert(newestCold)
        try context.save()

        let comments = try await CommentRepository(context: context).fetchComments(postId: "post-comments-order")

        #expect(comments.map(\.id) == [newHot.id, oldHot.id, newestCold.id])
    }

    @Test func userFacingErrorIconsDoNotUseExclamationPlaceholders() async throws {
        let states: [ErrorState] = [
            .offline,
            .databaseRecoveryMode(message: "recovering", technicalDetails: "SwiftData failed"),
            .requestFailed(message: "failed", technicalDetails: "debug")
        ]

        #expect(states.allSatisfy { !$0.systemImage.contains("exclamationmark") })
    }

    @Test func tabBarHiddenDoesNotFollowNavigationDepth() async throws {
        let chrome = AppChromeState()

        chrome.setNavigationDepth(3, for: .home)
        #expect(!chrome.isTabBarHidden)

        chrome.setHidden(true, reason: .input)
        #expect(chrome.isTabBarHidden)

        chrome.setHidden(false, reason: .input)
        #expect(!chrome.isTabBarHidden)
    }

    @Test func selectingTopLevelTabClearsStaleTransientChromeReasons() async throws {
        let chrome = AppChromeState()

        chrome.setHidden(true, reason: .input)
        chrome.setHidden(true, reason: .conversation)
        chrome.setHidden(true, reason: .mediaPreview)
        chrome.setHidden(true, reason: .postDetail)
        #expect(chrome.isTabBarHidden)

        chrome.select(.search)

        #expect(!chrome.isTabBarHidden)
        #expect(chrome.selectedTab == .search)
    }

    @Test func postDetailRouteMetadataControlsChromeAndInitialFocus() async throws {
        #expect(KXRoute.postDetail(postId: "post-1").requiresHiddenTabBar)
        #expect(KXRoute.postDetail(postId: "post-1").initialFocus == .none)
        #expect(KXRoute.postDetailComment(postId: "post-1", commentId: nil).requiresHiddenTabBar)
        #expect(KXRoute.postDetailComment(postId: "post-1", commentId: nil).initialFocus == .comments)
        #expect(KXRoute.postDetailComment(postId: "post-1", commentId: "comment-1").initialFocus == .comment("comment-1"))
        #expect(!KXRoute.profile(userId: "user-1").requiresHiddenTabBar)
    }

    @Test func appRouterDrivesRouteBasedChromeVisibility() async throws {
        let router = AppRouter()

        #expect(!router.requiresHiddenChrome(for: .home))

        router.open(.profile(userId: "user-1"), in: .home)
        #expect(!router.requiresHiddenChrome(for: .home))
        #expect(router.pathCount(for: .home) == 1)

        router.open(.postDetail(postId: "post-1"), in: .home)
        #expect(router.requiresHiddenChrome(for: .home))
        #expect(router.pathCount(for: .home) == 2)

        router.popToRoot(.home)
        #expect(!router.requiresHiddenChrome(for: .home))
        #expect(router.pathCount(for: .home) == 0)
    }

    @Test func appChromeKeepsRouteReasonSeparateFromTransientReasons() async throws {
        let chrome = AppChromeState()

        chrome.setRouteHidden(true)
        chrome.setHidden(true, reason: .input)
        chrome.select(.search)

        #expect(chrome.isTabBarHidden)

        chrome.setRouteHidden(false)
        #expect(!chrome.isTabBarHidden)
    }

    @Test func appErrorMapsRepositoryFailuresToUserFriendlyMessages() async throws {
        #expect(AppError(RepositoryError.notFound) == .notFound)
        #expect(AppError(RepositoryError.mediaFailed).userMessage == "媒体处理失败，请换一个文件重试。")
        #expect((RepositoryError.validationFailed as Error).kaixUserMessage == "内容不完整，请检查后重试。")
    }

    @Test func productionBootstrapDoesNotCreateDemoContent() async throws {
        let context = try makeContext()

        try await DatabaseSeeder.bootstrapIfNeeded(context: context)

        #expect(try context.fetch(FetchDescriptor<UserEntity>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PostEntity>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MessageThreadEntity>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NotificationEntity>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TopicEntity>()).isEmpty)
    }

    @Test func newAccountAndComposerDoNotInjectPlaceholderContent() async throws {
        let context = try makeContext()
        let user = try await UserRepository(context: context).register(username: "real_user", displayName: "Real User", password: "secret123")
        let composer = ComposePostViewModel()

        await composer.loadSuggestedTopics(context: context)

        #expect(user.bio.isEmpty)
        #expect(user.location.isEmpty)
        #expect(composer.suggestedTopics.isEmpty)
    }

    @Test func searchLoadsDiscoveryShellWhenRealContentIsEmpty() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "real-user", username: "real_user", displayName: "Real User")
        context.insert(currentUser)
        try context.save()

        let viewModel = SearchViewModel()
        let searchStore = SearchStore()

        await viewModel.load(context: context, currentUser: currentUser, searchStore: searchStore)

        #expect(viewModel.state == .loaded)
        #expect(searchStore.loadingState == .loaded)
        #expect(viewModel.filteredTrendingItems.isEmpty)
        #expect(viewModel.filteredTopics.isEmpty)
        #expect(viewModel.filteredUsers.isEmpty)
    }

    @Test func regionDirectoryMirrorsCurrentLaunchCities() async throws {
        let popularCodes = KaiXRegionDirectory.popular.map(\.regionCode)

        #expect(popularCodes == KaiXRegionDirectory.popularRegionCodes)
        #expect(Array(popularCodes.prefix(8)) == [
            "cn.shanghai.shanghai",
            "cn.beijing.beijing",
            "cn.guangdong.shenzhen",
            "cn.guangdong.guangzhou",
            "cn.zhejiang.hangzhou",
            "cn.sichuan.chengdu",
            "cn.chongqing.chongqing",
            "cn.hubei.wuhan",
        ])
        #expect(popularCodes.contains("jp.tokyo.tokyo"))
        #expect(popularCodes.contains("jp.osaka.osaka"))
        #expect(popularCodes.contains("jp.aichi.nagoya"))
        #expect(popularCodes.contains("jp.kanagawa.yokohama"))
        #expect(popularCodes.contains("jp.hokkaido.sapporo"))

        #expect(KaiXRegionDirectory.resolve(regionCode: "jp.tokyo.tokyo")?.cityName == "东京")
        #expect(KaiXRegionDirectory.resolve(regionCode: "jp.osaka.osaka")?.cityName == "大阪")
        #expect(KaiXRegionDirectory.resolve(regionCode: "jp.aichi.nagoya")?.cityName == "名古屋")
        #expect(KaiXRegionDirectory.resolve(regionCode: "jp.kanagawa.yokohama")?.cityName == "横滨")
        #expect(KaiXRegionDirectory.resolve(regionCode: "jp.hokkaido.sapporo")?.cityName == "札幌")
        #expect(KaiXRegionDirectory.resolve(regionCode: "cn.zhejiang.hangzhou")?.cityName == "杭州")
        #expect(KaiXRegionDirectory.resolve(regionCode: "cn.jiangsu.suzhou")?.cityName == "苏州")
        #expect(KaiXRegionDirectory.cities(country: "cn", province: "zhejiang").map(\.code) == ["hangzhou", "ningbo"])
    }

    @Test func heatScoreMatchesCityPlatformFormula() async throws {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let createdAt = referenceDate.addingTimeInterval(-2 * 3600)

        let score = HeatScoreService.shared.calculate(
            viewCount: 999,
            likeCount: 2,
            commentCount: 3,
            repostCount: 1,
            bookmarkCount: 4,
            reportCount: 1,
            boostWeight: 7,
            boostedUntil: referenceDate.addingTimeInterval(60),
            createdAt: createdAt,
            referenceDate: referenceDate
        )

        #expect(score == 51)
    }

    @Test func databaseSeederPurgesSeededDemoContentAndKeepsRealContent() async throws {
        let context = try makeContext()
        let demoUser = UserEntity(id: "user-kaix", username: "kaizi", displayName: "KaiX News")
        let realUser = UserEntity(id: "real-user", username: "real_user", displayName: "Real User")
        let demoPost = PostEntity(id: "seed-post-1", authorId: demoUser.id, content: "Demo #SwiftUI", hashtags: ["swiftui"])
        let realPost = PostEntity(id: "real-post", authorId: realUser.id, content: "Real #Launch", hashtags: ["launch"])
        let demoComment = CommentEntity(id: "seed-comment-1", postId: demoPost.id, authorId: demoUser.id, content: "demo")
        let realComment = CommentEntity(id: "real-comment", postId: realPost.id, authorId: realUser.id, content: "real")
        let demoThread = MessageThreadEntity(id: "starter-thread-real-demo", participantIds: [realUser.id, demoUser.id])
        let demoMessage = MessageEntity(id: "starter-message-1", threadId: demoThread.id, senderId: demoUser.id, content: "demo")
        let realThread = MessageThreadEntity(id: "real-thread", participantIds: [realUser.id, "peer"])
        let realMessage = MessageEntity(id: "real-message", threadId: realThread.id, senderId: realUser.id, content: "real")

        context.insert(demoUser)
        context.insert(realUser)
        context.insert(demoPost)
        context.insert(realPost)
        context.insert(demoComment)
        context.insert(realComment)
        context.insert(MediaEntity(id: "demo-media", postId: demoPost.id, type: .image))
        context.insert(MediaEntity(id: "real-media", postId: realPost.id, type: .image))
        context.insert(NotificationEntity(id: "seed-notification-1", type: .comment, actorId: demoUser.id, targetPostId: demoPost.id, content: "demo"))
        context.insert(NotificationEntity(id: "real-notification", type: .comment, actorId: realUser.id, targetPostId: realPost.id, content: "real"))
        context.insert(FollowEntity(id: "demo-follow", followerId: realUser.id, followingId: demoUser.id))
        context.insert(demoThread)
        context.insert(demoMessage)
        context.insert(realThread)
        context.insert(realMessage)
        context.insert(TopicEntity(name: "swiftui", postCount: 1, heatScore: 100))
        context.insert(TopicEntity(name: "launch", postCount: 1, heatScore: 50))
        try context.save()

        let didPurge = try DatabaseSeeder.purgeDemoData(context: context)

        #expect(didPurge)
        #expect(try context.fetch(FetchDescriptor<UserEntity>()).map(\.id) == [realUser.id])
        #expect(try context.fetch(FetchDescriptor<PostEntity>()).map(\.id) == [realPost.id])
        #expect(try context.fetch(FetchDescriptor<CommentEntity>()).map(\.id) == [realComment.id])
        #expect(try context.fetch(FetchDescriptor<MediaEntity>()).map(\.id) == ["real-media"])
        #expect(try context.fetch(FetchDescriptor<NotificationEntity>()).map(\.id) == ["real-notification"])
        #expect(try context.fetch(FetchDescriptor<FollowEntity>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MessageThreadEntity>()).map(\.id) == [realThread.id])
        #expect(try context.fetch(FetchDescriptor<MessageEntity>()).map(\.id) == [realMessage.id])
        #expect(try context.fetch(FetchDescriptor<TopicEntity>()).map(\.name) == ["launch"])
    }

    @Test func composeTopicSelectionDeduplicatesCaseHashAndWhitespace() async throws {
        let viewModel = ComposePostViewModel()

        viewModel.content = "hello #AI"
        viewModel.addTopic(" ai ")
        viewModel.addTopic("#Ai")
        viewModel.addTopic("Agent")

        #expect(viewModel.content == "hello #AI")
        #expect(viewModel.selectedTopics == ["ai", "agent"])
    }

    @Test func createPostStoresExplicitTagsOutsideContent() async throws {
        let context = try makeContext()
        let repository = PostRepository(context: context)

        let post = try await repository.createPost(
            authorId: "user-tags",
            content: "hello",
            mediaDrafts: [],
            hashtags: ["#签证", " 求职 ", "#签证"]
        )

        #expect(post.content == "hello")
        #expect(post.hashtags == ["签证", "求职"])
    }

    @Test func messageStoreMirrorsUnreadCountsAndQueuesUploads() async throws {
        let store = MessageStore()
        let thread = MessageThreadEntity(id: "thread-store", participantIds: ["a", "b"], unreadCount: 3)
        let draft = MediaDraft(
            id: "draft-video",
            type: .video,
            localURL: URL(fileURLWithPath: "/tmp/video.mov"),
            thumbnailURL: URL(fileURLWithPath: "/tmp/video.jpg"),
            contentType: "video/quicktime",
            fileName: "video.mov",
            width: 100,
            height: 100,
            duration: 4
        )

        store.setConversations([thread])
        #expect(store.unreadCounts[thread.id] == 3)

        store.setUnreadCount(0, conversationId: thread.id)
        #expect(store.unreadCounts[thread.id] == 0)
        #expect(thread.unreadCount == 0)

        store.enqueueUpload(draft)
        #expect(store.uploadQueue.map(\.id) == [draft.id])
        store.removeUpload(draft.id)
        #expect(store.uploadQueue.isEmpty)
    }

    @Test func awsReadyMappersPreserveRemoteIdentityAndMediaType() async throws {
        let user = UserEntity(
            id: "user-local",
            username: "User.Name",
            displayName: "User",
            avatarURL: "/avatar.png",
            coverURL: "/cover.png",
            bio: "Bio",
            location: "Tokyo",
            isVerified: true,
            role: .creator,
            followerCount: 12,
            followingCount: 3,
            remoteId: "user-remote",
            syncStatus: .synced,
            cursor: "cursor-user"
        )
        let userDTO = KXUserMapper.dto(from: user)

        #expect(userDTO.id == "user-remote")
        #expect(userDTO.username == "user.name")
        #expect(userDTO.role == UserRole.creator.rawValue)
        #expect(userDTO.cursor == "cursor-user")

        let media = MediaEntity(
            id: "media-local",
            postId: "post-1",
            type: .video,
            localURL: "/video.mov",
            thumbnailURL: "/thumb.jpg",
            width: 1920,
            height: 1080,
            duration: 8,
            remoteId: "media-remote"
        )
        let mediaDTO = KXMediaMapper.dto(from: media)

        #expect(mediaDTO.id == "media-remote")
        #expect(mediaDTO.type == MediaType.video.rawValue)
        #expect(mediaDTO.duration == 8)

        let hydratedMedia = MediaEntity(id: "media-hydrated", postId: "old", type: .image)
        KXMediaMapper.apply(mediaDTO, to: hydratedMedia)

        #expect(hydratedMedia.remoteId == "media-remote")
        #expect(hydratedMedia.postId == "post-1")
        #expect(hydratedMedia.type == .video)
        #expect(hydratedMedia.syncStatus == .synced)
    }

    @Test func commentStoreRemovesParentAndRepliesFromCount() async throws {
        let store = CommentStore()
        let parent = CommentEntity(id: "comment-parent", postId: "post-comments", authorId: "a", content: "Parent")
        let reply = CommentEntity(id: "comment-reply", postId: "post-comments", authorId: "b", content: "Reply", parentCommentId: parent.id)

        store.setComments([parent, reply], postId: parent.postId, expectedCount: 2)
        store.removeComment(parent)

        #expect(store.commentsByPostId[parent.postId]?.isEmpty == true)
        #expect(store.commentCountsByPostId[parent.postId] == 0)
        #expect(store.loadingStateByPostId[parent.postId] == .empty)
    }

    @Test func repostIsUniqueAndCanBeUndone() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let author = UserEntity(id: "user-author", username: "author", displayName: "Author")
        let post = PostEntity(id: "post-1", authorId: author.id, content: "A shared post")
        context.insert(currentUser)
        context.insert(author)
        context.insert(post)
        try context.save()

        let store = PostStore()
        store.register(post)

        try await store.repostPost(context: context, postId: post.id, currentUser: currentUser)
        try await store.repostPost(context: context, postId: post.id, currentUser: currentUser)

        let reposts = try context.fetch(FetchDescriptor<PostEntity>()).filter { $0.repostOfPostId == post.id }
        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>()).filter {
            $0.type == .repost && $0.actorId == currentUser.id && $0.targetPostId == post.id
        }

        #expect(post.repostCount == 1)
        #expect(post.isRepostedByCurrentUser)
        #expect(reposts.count == 1)
        #expect(reposts.first?.content == "")
        #expect(notifications.count == 1)

        try await store.undoRepost(context: context, postId: post.id, currentUser: currentUser)
        try await store.undoRepost(context: context, postId: post.id, currentUser: currentUser)

        let remainingReposts = try context.fetch(FetchDescriptor<PostEntity>()).filter { $0.repostOfPostId == post.id }
        #expect(post.repostCount == 0)
        #expect(!post.isRepostedByCurrentUser)
        #expect(remainingReposts.isEmpty)
    }

    @Test func repostPrependsLocalFeedWithoutFullReload() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let author = UserEntity(id: "user-author", username: "author", displayName: "Author")
        let post = PostEntity(id: "post-feed-repost", authorId: author.id, content: "Fast repost")
        context.insert(currentUser)
        context.insert(author)
        context.insert(post)
        try context.save()

        let store = PostStore()
        store.setFeed([post])

        let repost = try await store.repostPost(context: context, postId: post.id, currentUser: currentUser)

        let repostId = try #require(repost?.id)
        #expect(store.feedIds.first == repostId)
        #expect(store.post(id: repostId)?.repostOfPostId == post.id)
        #expect(post.repostCount == 1)

        try await store.undoRepost(context: context, postId: post.id, currentUser: currentUser)

        #expect(!store.feedIds.contains(repostId))
        #expect(post.repostCount == 0)
    }

    @Test func postStoreKeepsFeedAndDetailStateInSync() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let author = UserEntity(id: "user-author", username: "author", displayName: "Author")
        let post = PostEntity(id: "post-sync", authorId: author.id, content: "Shared state")
        context.insert(currentUser)
        context.insert(author)
        context.insert(post)
        try context.save()

        let store = PostStore()
        store.register(post)

        try await store.likePost(context: context, postId: post.id, currentUser: currentUser)
        #expect(store.post(id: post.id)?.isLikedByCurrentUser == true)
        #expect(post.likeCount == 1)

        store.updateCommentCount(postId: post.id, delta: 1)
        #expect(store.post(id: post.id)?.commentCount == 1)
        #expect(post.commentCount == 1)
    }

    @Test func postDetailEditUpdatesStoreWithoutFullReload() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let post = PostEntity(id: "post-edit-detail", authorId: currentUser.id, content: "Old body #News")
        context.insert(currentUser)
        context.insert(post)
        try context.save()

        let store = PostStore()
        store.setFeed([post])

        let viewModel = PostDetailViewModel()
        viewModel.post = post
        viewModel.state = .loaded

        let didUpdate = await viewModel.updatePost(
            context: context,
            content: "  Updated body #SwiftUI  ",
            postStore: store
        )

        #expect(didUpdate)
        #expect(viewModel.state == .loaded)
        #expect(post.content == "Updated body #SwiftUI")
        #expect(post.hashtags == ["swiftui"])
        #expect(store.post(id: post.id)?.content == "Updated body #SwiftUI")
        #expect(store.feedIds == [post.id])
    }

    @Test func deletingOriginalPostRemovesRepostsAndRelatedData() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let peer = UserEntity(id: "user-peer", username: "peer", displayName: "Peer")
        let post = PostEntity(id: "post-delete-detail", authorId: currentUser.id, content: "Remove me")
        let repost = PostEntity(id: "repost-delete-detail", authorId: peer.id, content: "", repostOfPostId: post.id)
        let originalComment = CommentEntity(id: "comment-delete-original", postId: post.id, authorId: peer.id, content: "Original comment")
        let repostComment = CommentEntity(id: "comment-delete-repost", postId: repost.id, authorId: currentUser.id, content: "Repost comment")
        let originalMedia = MediaEntity(id: "media-delete-original", postId: post.id, type: .image)
        let repostMedia = MediaEntity(id: "media-delete-repost", postId: repost.id, type: .image)
        let originalNotification = NotificationEntity(id: "notification-delete-original", type: .comment, actorId: peer.id, targetPostId: post.id, content: "commented")
        let repostNotification = NotificationEntity(id: "notification-delete-repost", type: .repost, actorId: peer.id, targetPostId: repost.id, content: "reposted")
        context.insert(currentUser)
        context.insert(peer)
        context.insert(post)
        context.insert(repost)
        context.insert(originalComment)
        context.insert(repostComment)
        context.insert(originalMedia)
        context.insert(repostMedia)
        context.insert(originalNotification)
        context.insert(repostNotification)
        try context.save()

        let store = PostStore()
        store.setFeed([repost, post])
        store.setSearchResults([post, repost])
        store.setProfilePosts([post], userId: currentUser.id)
        store.setProfilePosts([repost], userId: peer.id)

        let viewModel = PostDetailViewModel()
        viewModel.post = post
        viewModel.state = .loaded

        let didDelete = await viewModel.deletePost(context: context, postStore: store)

        let remainingPosts = try context.fetch(FetchDescriptor<PostEntity>())
        let remainingComments = try context.fetch(FetchDescriptor<CommentEntity>())
        let remainingMedia = try context.fetch(FetchDescriptor<MediaEntity>())
        let remainingNotifications = try context.fetch(FetchDescriptor<NotificationEntity>())

        #expect(didDelete)
        #expect(viewModel.post == nil)
        #expect(viewModel.state == .empty)
        #expect(store.post(id: post.id) == nil)
        #expect(store.post(id: repost.id) == nil)
        #expect(store.feedIds.isEmpty)
        #expect(store.searchResultIds.isEmpty)
        #expect(store.profilePostIds[currentUser.id]?.isEmpty == true)
        #expect(store.profilePostIds[peer.id]?.isEmpty == true)
        #expect(remainingPosts.isEmpty)
        #expect(remainingComments.isEmpty)
        #expect(remainingMedia.isEmpty)
        #expect(remainingNotifications.isEmpty)
    }

    @Test func repostDoesNotDoubleCountWhenPersistedStateAlreadyExists() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let author = UserEntity(id: "user-author", username: "author", displayName: "Author")
        let post = PostEntity(id: "post-existing-repost", authorId: author.id, content: "Already reposted", repostCount: 1)
        let existingRepost = PostEntity(id: "repost-existing", authorId: currentUser.id, content: post.content, repostOfPostId: post.id)
        context.insert(currentUser)
        context.insert(author)
        context.insert(post)
        context.insert(existingRepost)
        try context.save()

        let store = PostStore()
        store.register(post)
        post.isRepostedByCurrentUser = false

        try await store.repostPost(context: context, postId: post.id, currentUser: currentUser)

        let reposts = try context.fetch(FetchDescriptor<PostEntity>()).filter { $0.repostOfPostId == post.id }
        #expect(reposts.count == 1)
        #expect(post.repostCount == 1)
        #expect(post.isRepostedByCurrentUser)
    }

    @Test func quoteRepostIncrementsOnceAndKeepsOriginalPostContent() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let author = UserEntity(id: "user-author", username: "author", displayName: "Author")
        let post = PostEntity(id: "post-quote", authorId: author.id, content: "Original text", repostCount: 0)
        context.insert(currentUser)
        context.insert(author)
        context.insert(post)
        try context.save()

        let store = PostStore()
        store.register(post)

        let quote = try await store.quoteRepost(context: context, postId: post.id, currentUser: currentUser, content: "My take #SwiftUI")
        let reposts = try context.fetch(FetchDescriptor<PostEntity>()).filter { $0.repostOfPostId == post.id }

        #expect(post.repostCount == 1)
        #expect(post.content == "Original text")
        #expect(quote.content == "My take #SwiftUI")
        #expect(quote.hashtags == ["swiftui"])
        #expect(reposts.count == 1)
    }

    @Test func ordinaryRepostDoesNotTreatQuoteAsDuplicate() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let author = UserEntity(id: "user-author", username: "author", displayName: "Author")
        let post = PostEntity(id: "post-quote-then-repost", authorId: author.id, content: "Original text", repostCount: 0)
        context.insert(currentUser)
        context.insert(author)
        context.insert(post)
        try context.save()

        let repository = PostRepository(context: context)
        _ = try await repository.quoteRepost(post: post, currentUserId: currentUser.id, content: "A quoted view")
        _ = try await repository.repost(post: post, currentUserId: currentUser.id)

        let reposts = try context.fetch(FetchDescriptor<PostEntity>()).filter { $0.repostOfPostId == post.id }
        #expect(post.repostCount == 2)
        #expect(reposts.contains { $0.content == "A quoted view" })
        #expect(reposts.contains { $0.content.isEmpty })
    }

    @Test func commentNotificationKeepsTargetCommentId() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let commenter = UserEntity(id: "user-commenter", username: "commenter", displayName: "Commenter")
        let post = PostEntity(id: "post-comment-target", authorId: currentUser.id, content: "Target", commentCount: 0)
        context.insert(currentUser)
        context.insert(commenter)
        context.insert(post)
        try context.save()

        let comment = try await PostRepository(context: context).addComment(
            post: post,
            authorId: commenter.id,
            content: "A precise comment"
        )

        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>()).filter {
            $0.type == .comment && $0.targetPostId == post.id
        }

        #expect(notifications.count == 1)
        #expect(notifications.first?.targetCommentId == comment.id)
    }

    @Test func dataIntegrityRepairerFixesCommentCountMismatchAndDuplicateNotifications() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let author = UserEntity(id: "user-author", username: "author", displayName: "Author")
        let post = PostEntity(id: "post-integrity", authorId: author.id, content: "Integrity check", commentCount: 4)
        context.insert(currentUser)
        context.insert(author)
        context.insert(post)
        context.insert(NotificationEntity(id: "n1", type: .repost, actorId: currentUser.id, targetPostId: post.id, content: "转发了你的帖子"))
        context.insert(NotificationEntity(id: "n2", type: .repost, actorId: currentUser.id, targetPostId: post.id, content: "转发了你的帖子"))
        try context.save()

        try DataIntegrityRepairer.repair(context: context)

        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>())
        #expect(post.commentCount == 0)
        #expect(notifications.count == 1)
    }

    @Test func dataIntegrityRepairerRemovesImagePlaceholderFromMessageBody() async throws {
        let context = try makeContext()
        let thread = MessageThreadEntity(id: "thread-image", participantIds: ["a", "b"], lastMessage: "[图片] [图片]")
        let message = MessageEntity(
            id: "message-image",
            threadId: thread.id,
            senderId: "a",
            content: "[图片]",
            mediaItemIds: ["media-image"],
            createdAt: .now
        )
        let media = MediaEntity(id: "media-image", postId: message.id, type: .image)
        context.insert(thread)
        context.insert(message)
        context.insert(media)
        try context.save()

        try DataIntegrityRepairer.repair(context: context)

        #expect(message.content.isEmpty)
        #expect(thread.lastMessage == "[图片]")
        #expect(message.type == .image)
    }

    @Test func missingPostDetailUsesEmptyStateInsteadOfErrorPlaceholder() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        context.insert(currentUser)
        try context.save()

        let viewModel = PostDetailViewModel()
        await viewModel.load(context: context, postId: "missing-post", currentUser: currentUser, postStore: PostStore())

        #expect(viewModel.state == .empty)
        #expect(viewModel.post == nil)
    }

    @Test func searchRankingUsesDisplayTitleAndTargetsOriginalPost() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let author = UserEntity(id: "user-author", username: "author", displayName: "Author")
        let post = PostEntity(
            id: "post-ranking",
            authorId: author.id,
            content: "AI 应用正在从聊天窗口转向任务型工作流。第二句应该不进入标题。 #AI #Agent",
            viewCount: 42,
            heatScore: 100
        )
        let repost = PostEntity(id: "repost-ranking", authorId: currentUser.id, content: post.content, heatScore: 120, repostOfPostId: post.id)
        context.insert(currentUser)
        context.insert(author)
        context.insert(post)
        context.insert(repost)
        try context.save()

        let viewModel = SearchViewModel()
        await viewModel.load(context: context, currentUser: currentUser, postStore: PostStore())

        let topItem = try #require(viewModel.trendingItems.first)
        #expect(topItem.title == "AI 应用正在从聊天窗口转向任务型工作流")
        #expect(topItem.title != post.content)
        #expect(topItem.postId == post.id)
    }

    @Test func tagsNormalizeAndDeduplicateForDisplay() {
        let tags = ["#AI", " ai ", "Ai", "#Agent", "agent"]

        #expect(tags.normalizedDisplayHashtags == ["ai", "agent"])
        #expect(tags.normalizedHashtagStorage == "ai|agent")
    }

    @Test func videoMessageResolvesAsVideoWithoutPlaceholderText() {
        let message = MessageEntity(
            id: "message-video",
            threadId: "thread-video",
            senderId: "sender",
            content: "",
            mediaItemIds: ["media-video"]
        )
        let media = MediaEntity(id: "media-video", postId: message.id, type: .video)

        #expect(message.visibleContent == nil)
        #expect(message.resolvedType(mediaItems: [media]) == .video)
    }

    @Test func failedMessageRetryMarksMessageSent() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let peer = UserEntity(id: "user-peer", username: "peer", displayName: "Peer")
        let thread = MessageThreadEntity(id: "thread-retry", participantIds: [currentUser.id, peer.id], lastMessage: "Pending")
        let message = MessageEntity(id: "message-retry", threadId: thread.id, senderId: currentUser.id, content: "Retry me", status: .failed)
        context.insert(currentUser)
        context.insert(peer)
        context.insert(thread)
        context.insert(message)
        try context.save()

        let viewModel = ChatViewModel()
        await viewModel.retryMessage(context: context, thread: thread, message: message)

        #expect(message.status == .sent)
        #expect(viewModel.messages.contains { $0.id == message.id })
    }

    @Test func sendingMessageAppendsLocallyAndUpdatesStore() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current", username: "current", displayName: "Current")
        let peer = UserEntity(id: "user-peer", username: "peer", displayName: "Peer")
        let thread = MessageThreadEntity(id: "thread-send", participantIds: [currentUser.id, peer.id])
        context.insert(currentUser)
        context.insert(peer)
        context.insert(thread)
        try context.save()

        let viewModel = ChatViewModel()
        let store = MessageStore()
        viewModel.inputText = "Hello"

        await viewModel.send(context: context, thread: thread, currentUser: currentUser, messageStore: store)

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages.first?.content == "Hello")
        #expect(viewModel.messages.first?.status == .sent)
        #expect(store.messagesByConversationId[thread.id]?.count == 1)
        #expect(thread.lastMessage == "Hello")
    }

    @Test func messageReadDeleteAndMessageRemovalStaySyncedWithStore() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "user-current-sync", username: "currentSync", displayName: "Current")
        let peer = UserEntity(id: "user-peer-sync", username: "peerSync", displayName: "Peer")
        let thread = MessageThreadEntity(id: "thread-sync", participantIds: [currentUser.id, peer.id], unreadCount: 2)
        let first = MessageEntity(id: "message-sync-1", threadId: thread.id, senderId: peer.id, content: "First")
        let second = MessageEntity(id: "message-sync-2", threadId: thread.id, senderId: currentUser.id, content: "Second")
        context.insert(currentUser)
        context.insert(peer)
        context.insert(thread)
        context.insert(first)
        context.insert(second)
        try context.save()

        let store = MessageStore()
        store.setConversations([thread])
        store.setMessages([first, second], conversationId: thread.id)

        let messagesViewModel = MessagesViewModel()
        messagesViewModel.threads = [thread]
        await messagesViewModel.toggleRead(context: context, thread: thread, messageStore: store)
        #expect(store.unreadCounts[thread.id] == 0)

        await messagesViewModel.toggleRead(context: context, thread: thread, messageStore: store)
        #expect(store.unreadCounts[thread.id] == 1)

        let chatViewModel = ChatViewModel()
        chatViewModel.messages = [first, second]
        await chatViewModel.deleteMessage(context: context, thread: thread, message: first, messageStore: store)
        #expect(store.messagesByConversationId[thread.id]?.map(\.id) == [second.id])

        await messagesViewModel.deleteThread(context: context, thread: thread, messageStore: store)
        #expect(store.conversationsById[thread.id] == nil)
        #expect(store.messagesByConversationId[thread.id] == nil)
        #expect(store.unreadCounts[thread.id] == nil)
    }

    @Test func notificationReadAndDeleteUpdateGroupedCacheLocally() async throws {
        let context = try makeContext()
        let actor = UserEntity(id: "notif-actor", username: "actor", displayName: "Actor")
        let secondActor = UserEntity(id: "notif-actor-2", username: "actor2", displayName: "Actor 2")
        let first = NotificationEntity(id: "notif-1", type: .like, actorId: actor.id, targetPostId: "post-1", content: "liked", isRead: false)
        let second = NotificationEntity(id: "notif-2", type: .like, actorId: secondActor.id, targetPostId: "post-1", content: "liked again", isRead: false)
        context.insert(actor)
        context.insert(secondActor)
        context.insert(first)
        context.insert(second)
        try context.save()

        let viewModel = NotificationsViewModel()
        let store = NotificationStore()
        await viewModel.load(context: context, notificationStore: store)

        #expect(viewModel.groupedNotifications.count == 1)
        #expect(store.unreadCount == 2)

        let aggregate = try #require(viewModel.groupedNotifications.first)
        await viewModel.markRead(context: context, aggregate: aggregate, notificationStore: store)

        #expect(viewModel.groupedNotifications.first?.isRead == true)
        #expect(store.unreadCount == 0)
        #expect(viewModel.state == .loaded)

        let readAggregate = try #require(viewModel.groupedNotifications.first)
        await viewModel.delete(context: context, aggregate: readAggregate, notificationStore: store)

        #expect(viewModel.notifications.isEmpty)
        #expect(viewModel.groupedNotifications.isEmpty)
        #expect(viewModel.state == .empty)
    }

    @Test func profileLikeInteractionUpdatesLocalListsWithoutReloadingProfile() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "profile-current", username: "current", displayName: "Current")
        let author = UserEntity(id: "profile-author", username: "author", displayName: "Author")
        let post = PostEntity(
            id: "profile-liked-post",
            authorId: author.id,
            content: "Liked post",
            likeCount: 1,
            isLikedByCurrentUser: true
        )
        context.insert(currentUser)
        context.insert(author)
        context.insert(post)
        try context.save()

        let viewModel = ProfileViewModel()
        let store = PostStore()
        store.register(post)
        viewModel.likedPosts = [post]
        viewModel.state = .loaded

        await viewModel.toggleLike(context: context, post: post, currentUser: currentUser, profileUser: currentUser, postStore: store)

        #expect(post.isLikedByCurrentUser == false)
        #expect(post.likeCount == 0)
        #expect(viewModel.likedPosts.isEmpty)
        #expect(viewModel.state == .loaded)
    }

    @Test func profileReloadReflectsNewPostAndInteractionStoreChanges() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "profile-live-current", username: "live_current", displayName: "Live Current")
        context.insert(currentUser)
        try context.save()

        let viewModel = ProfileViewModel()
        let store = PostStore()

        await viewModel.load(context: context, user: currentUser, postStore: store)
        #expect(viewModel.postCount == 0)
        #expect(store.profilePostIds[currentUser.id]?.isEmpty == true)

        let post = try await PostRepository(context: context).createPost(
            authorId: currentUser.id,
            content: "Profile should update immediately",
            mediaDrafts: []
        )
        store.insertPublishedPost(post, currentUserId: currentUser.id)

        #expect(store.profilePostIds[currentUser.id] == [post.id])

        await viewModel.load(context: context, user: currentUser, postStore: store)
        #expect(viewModel.postCount == 1)
        #expect(viewModel.authoredPosts.map(\.id) == [post.id])

        try await store.likePost(context: context, postId: post.id, currentUser: currentUser)
        await viewModel.load(context: context, user: currentUser, postStore: store)

        #expect(viewModel.likeCount == 1)
        #expect(viewModel.likedPosts.map(\.id) == [post.id])
    }

    @Test func userRepositoryFetchesFollowersAndFollowingForProfileLists() async throws {
        let context = try makeContext()
        let creator = UserEntity(id: "follow-creator", username: "creator", displayName: "Creator", followerCount: 20)
        let fan = UserEntity(id: "follow-fan", username: "fan", displayName: "Fan", followerCount: 1)
        let peer = UserEntity(id: "follow-peer", username: "peer", displayName: "Peer", followerCount: 5)
        let mentor = UserEntity(id: "follow-mentor", username: "mentor", displayName: "Mentor", followerCount: 100)
        context.insert(creator)
        context.insert(fan)
        context.insert(peer)
        context.insert(mentor)
        context.insert(FollowEntity(followerId: fan.id, followingId: creator.id))
        context.insert(FollowEntity(followerId: peer.id, followingId: creator.id))
        context.insert(FollowEntity(followerId: creator.id, followingId: mentor.id))
        try context.save()

        let repository = UserRepository(context: context)
        let followers = try await repository.fetchFollowers(userId: creator.id)
        let following = try await repository.fetchFollowing(userId: creator.id)

        #expect(followers.map(\.id) == [peer.id, fan.id])
        #expect(following.map(\.id) == [mentor.id])
    }

    @Test func followActionsPublishCountsToUserStore() async throws {
        let context = try makeContext()
        let currentUser = UserEntity(id: "follow-live-current", username: "follow_current", displayName: "Current")
        let target = UserEntity(id: "follow-live-target", username: "follow_target", displayName: "Target")
        context.insert(currentUser)
        context.insert(target)
        try context.save()

        let viewModel = SearchViewModel()
        let userStore = UserStore()

        await viewModel.toggleFollow(context: context, currentUser: currentUser, target: target, userStore: userStore)

        #expect(userStore.followStateByUserId[target.id] == true)
        #expect(userStore.followingCounts[currentUser.id] == 1)
        #expect(userStore.followerCounts[target.id] == 1)

        await viewModel.toggleFollow(context: context, currentUser: currentUser, target: target, userStore: userStore)

        #expect(userStore.followStateByUserId[target.id] == false)
        #expect(userStore.followingCounts[currentUser.id] == 0)
        #expect(userStore.followerCounts[target.id] == 0)
    }

    @Test func passwordStorageHashesAndUpgradesLegacyPlaintext() async throws {
        let context = try makeContext()
        let repository = UserRepository(context: context)
        let legacyUser = UserEntity(
            id: "legacy-user",
            username: "legacy",
            displayName: "Legacy",
            passwordHash: "secret123"
        )
        context.insert(legacyUser)
        try context.save()

        let loggedInLegacy = try await repository.login(username: "legacy", password: "secret123")
        #expect(loggedInLegacy?.id == legacyUser.id)
        #expect(legacyUser.passwordHash != "secret123")
        #expect(PasswordHasher.verify("secret123", storedHash: legacyUser.passwordHash))

        let registered = try await repository.register(username: "new_user", displayName: "New User", password: "another-secret")
        #expect(registered.passwordHash != "another-secret")
        #expect(PasswordHasher.verify("another-secret", storedHash: registered.passwordHash))
        #expect(try await repository.login(username: "new_user", password: "wrong") == nil)
    }

    @Test func usernameUpdateValidatesAndRejectsDuplicates() async throws {
        let context = try makeContext()
        let user = UserEntity(id: "rename-user", username: "old_name", displayName: "Old")
        let other = UserEntity(id: "rename-other", username: "taken", displayName: "Taken")
        context.insert(user)
        context.insert(other)
        try context.save()

        let repository = UserRepository(context: context)
        try await repository.updateUsername(user: user, username: " New.Name ")
        #expect(user.username == "new.name")

        do {
            try await repository.updateUsername(user: user, username: "taken")
            Issue.record("Duplicate usernames must be rejected.")
        } catch RepositoryError.duplicate {
            #expect(user.username == "new.name")
        }
    }

    @Test func deleteAccountRemovesLocalUserContent() async throws {
        let context = try makeContext()
        let user = UserEntity(id: "delete-user", username: "delete_me", displayName: "Delete Me")
        let peer = UserEntity(id: "peer-user", username: "peer", displayName: "Peer", followerCount: 1)
        let authoredPost = PostEntity(id: "delete-post", authorId: user.id, content: "Remove this")
        let peerPost = PostEntity(id: "peer-post", authorId: peer.id, content: "Keep this", commentCount: 3)
        let userComment = CommentEntity(id: "delete-comment", postId: peerPost.id, authorId: user.id, content: "Remove comment")
        let nestedReply = CommentEntity(id: "delete-nested-reply", postId: peerPost.id, authorId: peer.id, content: "Remove nested reply", parentCommentId: userComment.id)
        let deepReply = CommentEntity(id: "delete-deep-reply", postId: peerPost.id, authorId: user.id, content: "Remove deep reply", parentCommentId: nestedReply.id)
        let peerComment = CommentEntity(id: "peer-comment", postId: authoredPost.id, authorId: peer.id, content: "Remove with post")
        let thread = MessageThreadEntity(id: "delete-thread", participantIds: [user.id, peer.id], lastMessage: "bye")
        let message = MessageEntity(id: "delete-message", threadId: thread.id, senderId: user.id, content: "", mediaItemIds: ["delete-media-message"])

        context.insert(user)
        context.insert(peer)
        context.insert(authoredPost)
        context.insert(peerPost)
        context.insert(userComment)
        context.insert(nestedReply)
        context.insert(deepReply)
        context.insert(peerComment)
        context.insert(MediaEntity(id: "delete-media-post", postId: authoredPost.id, type: .image))
        context.insert(MediaEntity(id: "delete-media-message", postId: message.id, type: .image))
        context.insert(thread)
        context.insert(message)
        context.insert(NotificationEntity(id: "delete-notification", type: .comment, actorId: user.id, targetPostId: peerPost.id, content: "commented"))
        context.insert(FollowEntity(id: "delete-follow", followerId: user.id, followingId: peer.id))
        try context.save()

        try await UserRepository(context: context).deleteAccount(user: user)

        let users = try context.fetch(FetchDescriptor<UserEntity>())
        let posts = try context.fetch(FetchDescriptor<PostEntity>())
        let comments = try context.fetch(FetchDescriptor<CommentEntity>())
        let threads = try context.fetch(FetchDescriptor<MessageThreadEntity>())
        let messages = try context.fetch(FetchDescriptor<MessageEntity>())
        let media = try context.fetch(FetchDescriptor<MediaEntity>())
        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>())
        let follows = try context.fetch(FetchDescriptor<FollowEntity>())

        #expect(!users.contains { $0.id == user.id })
        #expect(!posts.contains { $0.id == authoredPost.id })
        #expect(posts.contains { $0.id == peerPost.id })
        #expect(peerPost.commentCount == 0)
        #expect(comments.isEmpty)
        #expect(threads.isEmpty)
        #expect(messages.isEmpty)
        #expect(media.isEmpty)
        #expect(notifications.isEmpty)
        #expect(follows.isEmpty)
        #expect(peer.followerCount == 0)
    }

    @Test func publicPostQueriesExcludeDraftAndFailedPosts() async throws {
        let context = try makeContext()
        let user = UserEntity(id: "filter-user", username: "filter", displayName: "Filter")
        let published = PostEntity(
            id: "published-post",
            authorId: user.id,
            content: "Visible #Launch",
            isLikedByCurrentUser: true,
            isBookmarkedByCurrentUser: true,
            status: .published,
            hashtags: ["launch"]
        )
        let draft = PostEntity(
            id: "draft-post",
            authorId: user.id,
            content: "Draft #Launch",
            isLikedByCurrentUser: true,
            isBookmarkedByCurrentUser: true,
            status: .draft,
            hashtags: ["launch"]
        )
        let failed = PostEntity(
            id: "failed-post",
            authorId: user.id,
            content: "Failed #Launch",
            isLikedByCurrentUser: true,
            status: .failed,
            hashtags: ["launch"]
        )
        context.insert(user)
        context.insert(published)
        context.insert(draft)
        context.insert(failed)
        try context.save()

        let repository = PostRepository(context: context)

        #expect(try await repository.fetchPosts(authorId: user.id).map(\.id) == [published.id])
        #expect(try await repository.fetchLikedPosts().map(\.id) == [published.id])
        #expect(try await repository.fetchBookmarkedPosts().map(\.id) == [published.id])
        #expect(try await repository.fetchPosts(ids: [published.id, draft.id, failed.id]).map(\.id) == [published.id])
        #expect(try await repository.fetchPosts(topic: "launch").map(\.id) == [published.id])
    }

    @Test func mediaOnlyDraftCanBePublishedWithoutText() async throws {
        let context = try makeContext()
        let user = UserEntity(id: "draft-user", username: "draft", displayName: "Draft")
        let draft = PostEntity(id: "media-draft", authorId: user.id, content: "", status: .draft)
        let media = MediaEntity(id: "draft-media", postId: draft.id, type: .video, localURL: "/tmp/video.mov", thumbnailURL: "/tmp/thumb.jpg")
        context.insert(user)
        context.insert(draft)
        context.insert(media)
        try context.save()

        let repository = PostRepository(context: context)
        try await repository.updateDraft(post: draft, content: "   ")
        try await repository.publishDraft(post: draft)

        #expect(draft.status == .published)
        #expect(draft.content.isEmpty)
    }

    @Test func messageThreadsMatchExactParticipantIds() async throws {
        let context = try makeContext()
        let thread = MessageThreadEntity(id: "thread-user-1", participantIds: ["user-1", "peer"], lastMessageAt: .now)
        let substringThread = MessageThreadEntity(id: "thread-user-10", participantIds: ["user-10", "peer"], lastMessageAt: .now.addingTimeInterval(-10))
        let groupThread = MessageThreadEntity(id: "thread-group", participantIds: ["user-1", "peer", "third"], lastMessageAt: .now.addingTimeInterval(-20))
        context.insert(thread)
        context.insert(substringThread)
        context.insert(groupThread)
        try context.save()

        let repository = MessageRepository(context: context)
        let threads = try await repository.fetchThreads(currentUserId: "user-1")
        let existing = try await repository.getOrCreateThread(currentUserId: "user-1", peerUserId: "peer")

        #expect(threads.map(\.id) == [thread.id, groupThread.id])
        #expect(existing.id == thread.id)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(KaiXDatabaseContainer.models)
        let configuration = ModelConfiguration("KaiXTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
