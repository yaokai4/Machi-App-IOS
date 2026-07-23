import Foundation

// MARK: - 社交面补充端点(活动编辑)
//
// 与 KaiXAPIClient+Social.swift 分开维护:该文件由社交安全/管理批次新增,
// 不动共享的 KaiXAPIClient.swift / +Social.swift。
//
// 服务端能力盘点(2026-07,web/server.py):
// - PATCH /api/machi-events/{id|slug} → api_event_update 存在,主办方/管理员可改。
//   服务端按 {**event, **data} 合并后整行清洗写回,因此**未携带的字段保持原值**,
//   本 payload 全部字段可选、nil 不编码(synthesized Encodable 对 Optional 走
//   encodeIfPresent),天然是安全的部分更新。
// - 房间/房间消息**没有**专属举报端点(/api/rooms/* 无 report 路由),房间成员
//   移除(kick)端点也不存在;举报走既有 POST /api/users/{id}/report(reportUser,
//   note 里带 room:/message: 上下文),kick 暂缺 UI。

extension KaiXAPIClient {

    /// 活动编辑的部分更新载荷:nil = 不改该字段(服务端保留原值)。
    /// 空字符串 = 明确清空(如取消结束时间时 ends_at = "")。
    /// 封面字段只在用户新传了图时携带,避免把已有封面清掉。
    struct UpdateEventPayload: Encodable {
        var title: String?
        var subtitle: String?
        var description: String?
        var category: String?
        var cover_url: String?
        var cover_file_id: String?
        var requires_approval: Bool?
        var starts_at: String?
        var ends_at: String?
        var venue_name: String?
        var address: String?
        var capacity: Int?
        var price_text: String?
        var external_url: String?
    }

    /// 主办方 / 管理员编辑活动(服务端强制权限)。返回刷新后的完整活动。
    func updateEvent(_ idOrSlug: String, _ payload: UpdateEventPayload) async throws -> KaiXEventDTO {
        struct Response: Decodable { let event: KaiXEventDTO }
        let data = try await request("PATCH", "/api/machi-events/\(idOrSlug.encodedPathSegment)", body: payload)
        let response: Response = try decode(data)
        return response.event
    }
}
