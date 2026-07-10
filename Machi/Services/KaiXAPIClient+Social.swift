import Foundation

// MARK: - 社交房间(交友 · 约局 · 约饭) + Machi 活动 DTOs
//
// Mirrors web/server_rooms.py + web/server_events.py. All optional fields stay
// optional so old servers / partial payloads keep decoding.

struct KaiXRoomDTO: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let room_type: String?
    let room_type_label: String?
    let host_user_id: String?
    let country_code: String?
    let city_slug: String?
    let region_code: String?
    let location_hint: String?
    let starts_at: String?
    let capacity: Int?
    let member_count: Int?
    let is_full: Bool?
    let status: String?
    let message_count: Int?
    let last_activity_at: String?
    let created_at: String?
    let members: [KaiXUserDTO]?
    let viewer_joined: Bool?
    let viewer_role: String?
    let cover_url: String?
    let cover_thumb_url: String?
    let cover_file_id: String?

    var typeKey: String { room_type ?? "chat" }
    var memberCountValue: Int { member_count ?? members?.count ?? 1 }
    var capacityValue: Int { capacity ?? 0 }
    var isOpen: Bool { (status ?? "open") == "open" }
    var joined: Bool { viewer_joined ?? false }
    var isHostViewer: Bool { (viewer_role ?? "") == "host" }
    /// 列表卡用缩略图(快),详情大图用原图。缩略图异步生成,未就绪时后端已回退原图。
    var coverThumbURL: URL? { ((cover_thumb_url?.isEmpty == false ? cover_thumb_url : cover_url))?.kaixMediaURL }
    var coverFullURL: URL? { (cover_url?.isEmpty == false ? cover_url : nil)?.kaixMediaURL }
}

struct KaiXRoomMessageDTO: Codable, Identifiable, Equatable {
    let id: String
    let content: String
    let kind: String?
    let created_at: String?
    let user: KaiXUserDTO?

    var isSystem: Bool { (kind ?? "text") == "system" }
}

struct KaiXRoomTypeDTO: Codable, Identifiable, Equatable {
    let key: String
    let label: String
    var id: String { key }
}

struct KaiXEventFormFieldDTO: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let field_type: String?
    let options: [String]?
    let required: Bool?

    var typeKey: String { field_type ?? "text" }
    var isRequired: Bool { required ?? false }
}

struct KaiXEventDTO: Codable, Identifiable, Equatable {
    let id: String
    let slug: String?
    let title: String
    let subtitle: String?
    let description: String?
    let category: String?
    let category_label: String?
    let cover_url: String?
    let starts_at: String?
    let ends_at: String?
    let timezone: String?
    let venue_name: String?
    let address: String?
    let country_code: String?
    let city_slug: String?
    let region_code: String?
    let capacity: Int?
    let price_text: String?
    let external_url: String?
    let partner_name: String?
    let status: String?
    let is_featured: Bool?
    let going_count: Int?
    let is_full: Bool?
    let organizer_user_id: String?
    let organizer: KaiXUserDTO?
    let attendees_preview: [KaiXUserDTO]?
    let viewer_status: String?
    let viewer_checked_in: Bool?
    let form_fields: [KaiXEventFormFieldDTO]?
    let cover_thumb_url: String?
    let cover_file_id: String?
    let requires_approval: Bool?
    let pending_count: Int?
    let waitlist_count: Int?
    let checked_in_count: Int?
    let created_at: String?

    var goingCountValue: Int { going_count ?? 0 }
    var viewerGoing: Bool { (viewer_status ?? "") == "going" }
    var viewerWaitlisted: Bool { (viewer_status ?? "") == "waitlist" }
    var viewerPending: Bool { (viewer_status ?? "") == "pending" }
    var viewerCheckedIn: Bool { viewer_checked_in ?? false }
    var requiresApproval: Bool { requires_approval ?? false }
    var pendingCountValue: Int { pending_count ?? 0 }
    var waitlistCountValue: Int { waitlist_count ?? 0 }
    var checkedInCountValue: Int { checked_in_count ?? 0 }
    /// 列表卡用缩略图(快),详情 hero 用原图。缩略图异步生成,未就绪时后端已回退原图。
    var coverThumbURL: URL? { ((cover_thumb_url?.isEmpty == false ? cover_thumb_url : cover_url))?.kaixMediaURL }
    var coverFullURL: URL? { (cover_url?.isEmpty == false ? cover_url : nil)?.kaixMediaURL }
    /// 活动网页短链(分享 / 二维码用),与 Web 端 /events/{slug} 一致。
    var webURL: URL {
        KaiXBackend.marketingSiteURL.appendingPathComponent("events/\((slug?.isEmpty == false ? slug! : id))")
    }
}

/// 主办方名单里的一条报名(含状态 / 签到 / 表单答案)。仅主办方 / 管理员可见。
struct KaiXEventAttendeeDTO: Codable, Identifiable, Equatable {
    let user: KaiXUserDTO?
    let user_id: String?
    let status: String?
    let checked_in: Bool?
    let checked_in_at: String?
    let answers: [String: String]?

    var id: String { user_id ?? user?.id ?? "" }
    var statusKey: String { status ?? "going" }
    var isCheckedIn: Bool { checked_in ?? false }
}

struct KaiXEventCategoryDTO: Codable, Identifiable, Equatable {
    let key: String
    let label: String
    var id: String { key }
}

// MARK: - API client

extension KaiXAPIClient {

    // ── rooms ────────────────────────────────────────────────────────────

    struct RoomsPage {
        let items: [KaiXRoomDTO]
        let total: Int
        let nextOffset: Int?
        let roomTypes: [KaiXRoomTypeDTO]
    }

    func rooms(
        citySlug: String? = nil,
        regionCode: String? = nil,
        countryCode: String? = nil,
        type: String? = nil,
        mine: Bool = false,
        offset: Int = 0,
        limit: Int = 20
    ) async throws -> RoomsPage {
        struct Response: Decodable {
            let items: [KaiXRoomDTO]
            let total: Int?
            let next_offset: Int?
            let room_types: [KaiXRoomTypeDTO]?
        }
        var q: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let citySlug, !citySlug.isEmpty { q.append(URLQueryItem(name: "city_slug", value: citySlug)) }
        if let regionCode, !regionCode.isEmpty { q.append(URLQueryItem(name: "region_code", value: regionCode)) }
        if let countryCode, !countryCode.isEmpty { q.append(URLQueryItem(name: "country_code", value: countryCode)) }
        if let type, !type.isEmpty { q.append(URLQueryItem(name: "type", value: type)) }
        if mine { q.append(URLQueryItem(name: "mine", value: "1")) }
        let data = try await request("GET", "/api/rooms", queryItems: q)
        let response: Response = try decode(data)
        return RoomsPage(
            items: response.items,
            total: response.total ?? response.items.count,
            nextOffset: response.next_offset,
            roomTypes: response.room_types ?? []
        )
    }

    func createRoom(
        title: String,
        description: String,
        roomType: String,
        countryCode: String,
        citySlug: String,
        regionCode: String,
        locationHint: String,
        startsAt: String,
        capacity: Int,
        coverURL: String = "",
        coverFileID: String = ""
    ) async throws -> KaiXRoomDTO {
        struct Body: Encodable {
            let title: String
            let description: String
            let room_type: String
            let country_code: String
            let city_slug: String
            let region_code: String
            let location_hint: String
            let starts_at: String
            let capacity: Int
            let cover_url: String
            let cover_file_id: String
        }
        struct Response: Decodable { let room: KaiXRoomDTO }
        // 创建类端点按库内约定带 Idempotency-Key:超时后响应丢失、用户手动重试
        // 不会重复开局,顺带让 request() 的安全自动重试生效。
        let data = try await request("POST", "/api/rooms", body: Body(
            title: title, description: description, room_type: roomType,
            country_code: countryCode, city_slug: citySlug, region_code: regionCode,
            location_hint: locationHint, starts_at: startsAt, capacity: capacity,
            cover_url: coverURL, cover_file_id: coverFileID
        ), idempotencyKey: "room-create-\(UUID().uuidString)")
        let response: Response = try decode(data)
        return response.room
    }

    func room(_ roomId: String) async throws -> KaiXRoomDTO {
        struct Response: Decodable { let room: KaiXRoomDTO }
        let data = try await request("GET", "/api/rooms/\(roomId.encodedPathSegment)")
        let response: Response = try decode(data)
        return response.room
    }

    func joinRoom(_ roomId: String) async throws -> KaiXRoomDTO {
        struct Response: Decodable { let room: KaiXRoomDTO }
        let data = try await request("POST", "/api/rooms/\(roomId.encodedPathSegment)/join", body: [String: String]())
        let response: Response = try decode(data)
        return response.room
    }

    /// Returns nil when the host left and the room was disbanded.
    func leaveRoom(_ roomId: String) async throws -> KaiXRoomDTO? {
        struct Response: Decodable { let room: KaiXRoomDTO?; let disbanded: Bool? }
        let data = try await request("POST", "/api/rooms/\(roomId.encodedPathSegment)/leave", body: [String: String]())
        let response: Response = try decode(data)
        return response.disbanded == true ? nil : response.room
    }

    func closeRoom(_ roomId: String) async throws -> KaiXRoomDTO {
        struct Response: Decodable { let room: KaiXRoomDTO }
        let data = try await request("PATCH", "/api/rooms/\(roomId.encodedPathSegment)", body: ["status": "closed"])
        let response: Response = try decode(data)
        return response.room
    }

    func deleteRoom(_ roomId: String) async throws {
        _ = try await request("DELETE", "/api/rooms/\(roomId.encodedPathSegment)")
    }

    struct RoomMessagesPage {
        let items: [KaiXRoomMessageDTO]
        let nextBefore: String?
    }

    func roomMessages(_ roomId: String, before: String? = nil, limit: Int = 50) async throws -> RoomMessagesPage {
        struct Response: Decodable { let items: [KaiXRoomMessageDTO]; let next_before: String? }
        var q: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let before, !before.isEmpty { q.append(URLQueryItem(name: "before", value: before)) }
        let data = try await request("GET", "/api/rooms/\(roomId.encodedPathSegment)/messages", queryItems: q)
        let response: Response = try decode(data)
        return RoomMessagesPage(items: response.items, nextBefore: response.next_before)
    }

    func sendRoomMessage(_ roomId: String, content: String) async throws -> KaiXRoomMessageDTO {
        struct Response: Decodable { let message: KaiXRoomMessageDTO }
        // 带 Idempotency-Key,弱网重试不会把同一条消息重复落库(与 DM sendMessage 同款)。
        let data = try await request("POST", "/api/rooms/\(roomId.encodedPathSegment)/messages",
                                     body: ["content": content],
                                     idempotencyKey: "room-msg-\(roomId)-\(UUID().uuidString)")
        let response: Response = try decode(data)
        return response.message
    }

    // ── events ───────────────────────────────────────────────────────────

    struct EventsPage {
        let items: [KaiXEventDTO]
        let total: Int
        let nextOffset: Int?
        let categories: [KaiXEventCategoryDTO]
    }

    func events(
        citySlug: String? = nil,
        regionCode: String? = nil,
        countryCode: String? = nil,
        category: String? = nil,
        when: String = "upcoming",
        featuredOnly: Bool = false,
        mine: Bool = false,
        offset: Int = 0,
        limit: Int = 20
    ) async throws -> EventsPage {
        struct Response: Decodable {
            let items: [KaiXEventDTO]
            let total: Int?
            let next_offset: Int?
            let categories: [KaiXEventCategoryDTO]?
        }
        var q: [URLQueryItem] = [
            URLQueryItem(name: "when", value: when),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let citySlug, !citySlug.isEmpty { q.append(URLQueryItem(name: "city_slug", value: citySlug)) }
        if let regionCode, !regionCode.isEmpty { q.append(URLQueryItem(name: "region_code", value: regionCode)) }
        if let countryCode, !countryCode.isEmpty { q.append(URLQueryItem(name: "country_code", value: countryCode)) }
        if let category, !category.isEmpty { q.append(URLQueryItem(name: "category", value: category)) }
        if featuredOnly { q.append(URLQueryItem(name: "featured", value: "1")) }
        if mine { q.append(URLQueryItem(name: "mine", value: "1")) }
        let data = try await request("GET", "/api/machi-events", queryItems: q)
        let response: Response = try decode(data)
        return EventsPage(
            items: response.items,
            total: response.total ?? response.items.count,
            nextOffset: response.next_offset,
            categories: response.categories ?? []
        )
    }

    func event(_ idOrSlug: String) async throws -> KaiXEventDTO {
        struct Response: Decodable { let event: KaiXEventDTO }
        let data = try await request("GET", "/api/machi-events/\(idOrSlug.encodedPathSegment)")
        let response: Response = try decode(data)
        return response.event
    }

    struct CreateEventPayload: Encodable {
        var title: String
        var subtitle: String = ""
        var description: String = ""
        var category: String = "party"
        var cover_url: String = ""
        var cover_file_id: String = ""
        var requires_approval: Bool = false
        var starts_at: String
        var ends_at: String = ""
        var venue_name: String = ""
        var address: String = ""
        var country_code: String = "jp"
        var city_slug: String = ""
        var region_code: String = ""
        var capacity: Int = 0
        var price_text: String = ""
        var external_url: String = ""
        var status: String = "published"
    }

    func createEvent(_ payload: CreateEventPayload) async throws -> KaiXEventDTO {
        struct Response: Decodable { let event: KaiXEventDTO }
        // 创建类端点按库内约定带 Idempotency-Key,防超时重试创建出重复活动。
        let data = try await request("POST", "/api/machi-events", body: payload,
                                     idempotencyKey: "event-create-\(UUID().uuidString)")
        let response: Response = try decode(data)
        return response.event
    }

    func registerForEvent(_ idOrSlug: String, answers: [String: String]) async throws -> KaiXEventDTO {
        struct Body: Encodable { let answers: [String: String] }
        struct Response: Decodable { let event: KaiXEventDTO }
        let data = try await request("POST", "/api/machi-events/\(idOrSlug.encodedPathSegment)/register", body: Body(answers: answers))
        let response: Response = try decode(data)
        return response.event
    }

    func cancelEventRegistration(_ idOrSlug: String) async throws -> KaiXEventDTO {
        struct Response: Decodable { let event: KaiXEventDTO }
        let data = try await request("DELETE", "/api/machi-events/\(idOrSlug.encodedPathSegment)/register")
        let response: Response = try decode(data)
        return response.event
    }

    /// Organizer / admin only — soft-deletes the event (server enforces).
    func deleteEvent(_ idOrSlug: String) async throws {
        _ = try await request("DELETE", "/api/machi-events/\(idOrSlug.encodedPathSegment)")
    }

    // ── 主办方工具(luma 式:名单 / 审核 / 签到 / 群发 / 加日历)────────────────

    struct EventAttendees {
        let items: [KaiXEventAttendeeDTO]
        let formFields: [KaiXEventFormFieldDTO]
        let total: Int
    }

    /// 主办方 / 管理员的完整报名名单(含表单答案),服务端强制权限。
    func eventAttendees(_ idOrSlug: String) async throws -> EventAttendees {
        struct Response: Decodable {
            let items: [KaiXEventAttendeeDTO]?
            let form_fields: [KaiXEventFormFieldDTO]?
            let total: Int?
        }
        let data = try await request("GET", "/api/machi-events/\(idOrSlug.encodedPathSegment)/attendees")
        let r: Response = try decode(data)
        return EventAttendees(items: r.items ?? [], formFields: r.form_fields ?? [], total: r.total ?? (r.items?.count ?? 0))
    }

    /// 通过一个待审核 / 候补的报名 → 转正(满员则转候补)。返回刷新后的活动。
    func approveRegistration(_ idOrSlug: String, userId: String) async throws -> KaiXEventDTO {
        struct Response: Decodable { let event: KaiXEventDTO }
        let data = try await request("POST", "/api/machi-events/\(idOrSlug.encodedPathSegment)/approve",
                                     body: ["user_id": userId])
        return (try decode(data) as Response).event
    }

    /// 拒绝 / 移除一个报名。返回刷新后的活动。
    func declineRegistration(_ idOrSlug: String, userId: String) async throws -> KaiXEventDTO {
        struct Response: Decodable { let event: KaiXEventDTO }
        let data = try await request("POST", "/api/machi-events/\(idOrSlug.encodedPathSegment)/decline",
                                     body: ["user_id": userId])
        return (try decode(data) as Response).event
    }

    /// 现场签到 / 取消签到一名正式参加者。
    func checkInAttendee(_ idOrSlug: String, userId: String, checkedIn: Bool) async throws {
        struct Body: Encodable { let user_id: String; let checked_in: Bool }
        _ = try await request("POST", "/api/machi-events/\(idOrSlug.encodedPathSegment)/checkin",
                              body: Body(user_id: userId, checked_in: checkedIn))
    }

    /// 给所有正式参加者群发一条公告(铃铛 + 尽力推送)。返回送达人数。
    @discardableResult
    func broadcastEvent(_ idOrSlug: String, message: String) async throws -> Int {
        struct Response: Decodable { let sent: Int? }
        let data = try await request("POST", "/api/machi-events/\(idOrSlug.encodedPathSegment)/broadcast",
                                     body: ["message": message])
        return (try decode(data) as Response).sent ?? 0
    }

    /// 「添加到日历」的服务端 .ics 绝对地址(交给系统 / 分享面板即可加进日历)。
    func eventCalendarURL(_ idOrSlug: String) -> URL? {
        var base = KaiXBackend.baseURL.absoluteString
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        return URL(string: "\(base)/api/machi-events/\(idOrSlug.encodedPathSegment)/calendar.ics")
    }

    /// 拉取活动的 .ics 文本(写临时文件后可走分享面板 → 加入日历,免日历权限)。
    func eventICS(_ idOrSlug: String) async throws -> String {
        let data = try await request("GET", "/api/machi-events/\(idOrSlug.encodedPathSegment)/calendar.ics")
        return String(data: data, encoding: .utf8) ?? ""
    }
}
