import Testing
@testable import Machi

@MainActor
struct NotificationRoutingTests {
    @Test func concreteTargetsTakePriorityOverLegacyType() {
        // Booking/review/status rows from the server may be represented as
        // `.system` by this client. Their concrete targets must still open.
        let conversation = NotificationRouteResolver.route(
            type: .system,
            actorId: nil,
            currentUserId: "me",
            postId: "post-fallback",
            commentId: nil,
            listingId: "listing-fallback",
            conversationId: "  conversation-1  "
        )
        #expect(conversation == .conversation(conversationId: "conversation-1"))
        #expect(conversation.map { NotificationRouteResolver.preferredTab(for: $0) } == .messages)

        let listing = NotificationRouteResolver.route(
            type: .system,
            actorId: nil,
            currentUserId: "me",
            postId: nil,
            commentId: nil,
            listingId: "listing-1",
            conversationId: nil
        )
        #expect(listing == .cityListingDetail(listingId: "listing-1"))
        #expect(listing.map { NotificationRouteResolver.preferredTab(for: $0) } == .search)
    }

    @Test func commentsAndTargetlessAnnouncementsRouteSafely() {
        let comment = NotificationRouteResolver.route(
            type: .comment,
            actorId: "actor",
            currentUserId: "me",
            postId: " post-1 ",
            commentId: " comment-1 ",
            listingId: nil,
            conversationId: nil
        )
        #expect(comment == .postDetailComment(postId: "post-1", commentId: "comment-1"))
        #expect(comment.map { NotificationRouteResolver.preferredTab(for: $0) } == .home)

        let announcement = NotificationRouteResolver.route(
            type: .cityDigest,
            actorId: nil,
            currentUserId: "me",
            postId: "   ",
            commentId: nil,
            listingId: nil,
            conversationId: nil
        )
        #expect(announcement == nil)
    }

    @Test func target404IsAnExpectedEmptyState() {
        let post404 = KaiXAPIError(error: .init(code: "post_not_found", message: "missing"))
        let listing404 = KaiXAPIError(error: .init(code: "listing_not_found", message: "missing"))
        let network = KaiXAPIError(error: .init(code: "http_503", message: "down"))

        #expect(post404.isKaiXResourceNotFound)
        #expect(listing404.isKaiXResourceNotFound)
        #expect(!network.isKaiXResourceNotFound)
    }
}
