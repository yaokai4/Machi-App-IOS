import Foundation

/// Admin-only API surface. Every endpoint is additionally gated server-side by
/// require_admin — the client-side role check only decides what UI to show.
extension KaiXAPIClient {
    /// Recent push-broadcast tasks (newest first) for the admin history list.
    func adminPushCampaigns(limit: Int = 50) async throws -> [KaiXPushCampaignDTO] {
        struct Wrapper: Decodable { let items: [KaiXPushCampaignDTO] }
        let data = try await request(
            "GET", "/api/admin/push-campaigns",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return (try decode(data) as Wrapper).items
    }

    /// Deliverable recipient count for an audience — shown before sending so the
    /// admin can confirm the blast size (seed/deleted accounts already excluded).
    func adminPushCampaignPreview(audience: String, userIds: [String]) async throws -> Int {
        struct Body: Encodable { let audience: String; let user_ids: [String] }
        struct Resp: Decodable { let count: Int }
        let data = try await request(
            "POST", "/api/admin/push-campaigns/preview",
            body: Body(audience: audience, user_ids: userIds)
        )
        return (try decode(data) as Resp).count
    }

    /// Create a push broadcast. With `sendNow`, the server queues delivery
    /// immediately (in-app notification row per recipient + APNs banner).
    func adminCreatePushCampaign(
        title: String,
        body: String,
        audience: String,
        userIds: [String],
        deepLinkType: String,
        deepLinkId: String,
        urgent: Bool,
        sendNow: Bool
    ) async throws -> KaiXPushCampaignDTO {
        struct Body: Encodable {
            let title: String
            let body: String
            let audience: String
            let user_ids: [String]
            let deepLinkType: String
            let deepLinkId: String
            let urgent: Bool
            let sendNow: Bool
        }
        struct Resp: Decodable { let campaign: KaiXPushCampaignDTO }
        let data = try await request(
            "POST", "/api/admin/push-campaigns",
            body: Body(
                title: title, body: body, audience: audience, user_ids: userIds,
                deepLinkType: deepLinkType, deepLinkId: deepLinkId, urgent: urgent, sendNow: sendNow
            )
        )
        return (try decode(data) as Resp).campaign
    }

    /// Send a previously-saved draft campaign.
    @discardableResult
    func adminSendPushCampaign(id: String) async throws -> KaiXPushCampaignDTO {
        struct Resp: Decodable { let campaign: KaiXPushCampaignDTO }
        let data = try await request("POST", "/api/admin/push-campaigns/\(id.encodedPathSegment)/send")
        return (try decode(data) as Resp).campaign
    }
}
