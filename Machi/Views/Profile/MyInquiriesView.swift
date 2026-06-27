import SwiftUI

/// Workbench inquiries manager — mirrors the Web 工作台 咨询 screen.
/// 收到: people contacting MY listings (buyer leads, job applications,
/// bookings). 发出: inquiries I sent to others. The record is the source of
/// truth; chat is only a follow-up channel.
struct MyInquiriesView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    let currentUser: UserEntity
    /// Workbench IA bucket: "consultation" (我的咨询), "reservation" (我的预约),
    /// or "application" (我的申请). Keeps each record under one entry only.
    var bucket: String = "consultation"
    /// Optional nav title override (defaults to 我的咨询).
    var navTitle: String? = nil
    /// When embedded in a hub (e.g. 我的预约), suppress the standalone nav title.
    var embedded: Bool = false

    private enum Role: String, CaseIterable, Identifiable {
        case received, sent
        var id: String { rawValue }
        func title(_ language: AppLanguage) -> String {
            switch self {
            case .received: L("inquiriesReceived", language)
            case .sent: L("inquiriesSent", language)
            }
        }
    }

    @State private var role: Role = .received
    @State private var itemsByRole: [Role: [KaiXListingInquiryDTO]] = [:]
    @State private var state: ScreenState = .idle
    @State private var updatingInquiryId: String?

    var body: some View {
        VStack(spacing: 0) {
            KXSegmentedControl(Role.allCases, selection: $role) { item in
                Text(item.title(language))
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.vertical, 10)

            content
        }
        .navigationTitle(embedded ? "" : (navTitle ?? L("inquiriesTitle", language)))
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .task(id: role) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        let items = itemsByRole[role] ?? []
        switch state {
        case .idle, .loading:
            if items.isEmpty {
                KXInlineLoader().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(items)
            }
        case .error(let message):
            ErrorStateView(message: message) { Task { await load(force: true) } }
        case .empty:
            EmptyStateView(
                title: L("inquiriesEmpty", language),
                subtitle: L("inquiriesEmptyHelp", language),
                systemImage: "tray"
            )
        case .loaded:
            list(items)
        }
    }

    private func list(_ items: [KaiXListingInquiryDTO]) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { inquiry in
                    row(inquiry)
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 10)
            .kxTabBarSafeBottomPadding()
        }
        .refreshable { await load(force: true) }
    }

    private func row(_ inquiry: KaiXListingInquiryDTO) -> some View {
        let counterpart = role == .received ? inquiry.resolvedFromUser : inquiry.resolvedToUser
        let details = normalizedDetails(inquiry)
        let cleanMessage = clean(inquiry.message)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(statusColor(inquiry.status ?? "submitted").opacity(0.12))
                    Image(systemName: typeIcon(inquiry.type ?? "general"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(statusColor(inquiry.status ?? "submitted"))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        typeChip(inquiry.type ?? "general")
                        statusChip(inquiry.status ?? "submitted")
                    }

                    Text(inquiry.listing?.title ?? L("inquiryListingGone", language))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let name = counterpart?.display_name ?? counterpart?.displayName, !name.isEmpty {
                            Text(role == .received ? LabeledCopy.applicant(name, language) : LabeledCopy.counterpart(name, language))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        let timestamp = inquiry.resolvedUpdatedAt.isEmpty ? inquiry.resolvedCreatedAt : inquiry.resolvedUpdatedAt
                        if !timestamp.isEmpty {
                            Text(formattedDate(timestamp))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(details.prefix(4).enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.label)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 68, alignment: .leading)
                            Text(line.value)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary.opacity(0.86))
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(10)
                .background(KXColor.softBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if !cleanMessage.isEmpty {
                Text(cleanMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Plain-language hint so the status actually means something to the
            // user ("新咨询，尽快联系" beats a bare "submitted" tag).
            if let hint = LabeledCopy.statusHint(inquiry.status ?? "submitted", isReceived: role == .received, language: language) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption2)
                    Text(hint)
                        .font(.caption2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(statusColor(inquiry.status ?? "submitted"))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(statusColor(inquiry.status ?? "submitted").opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            HStack(spacing: 8) {
                actionButton(title: LabeledCopy.viewDetail(language), icon: "doc.text.magnifyingglass", filled: false) {
                    openListing(inquiry)
                }
                actionButton(title: role == .received ? LabeledCopy.followUpApplicant(language) : LabeledCopy.followUpMessage(language), icon: "bubble.left.and.bubble.right.fill", filled: true) {
                    openConversation(inquiry)
                }
            }

            // One tidy "更新进度" menu replaces the old cramped 7-pill
            // horizontal scroll — the current status is always visible and
            // the next steps live in a clean dropdown.
            if role == .received {
                statusUpdateMenu(inquiry)
            } else {
                HStack(spacing: 8) {
                    if !isTerminalStatus(inquiry.status ?? "submitted") {
                        statusAction(inquiry, status: "withdrawn", title: LabeledCopy.withdraw(language), icon: "arrow.uturn.backward.circle.fill")
                    }
                    destructiveAction(title: LabeledCopy.closeRecord(language), icon: "archivebox.fill") {
                        Task { await deleteInquiry(inquiry) }
                    }
                }
            }
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private func isTerminalStatus(_ status: String) -> Bool {
        ["rejected", "withdrawn", "completed", "closed", "spam", "reported"].contains(status)
    }

    @ViewBuilder
    private func statusUpdateMenu(_ inquiry: KaiXListingInquiryDTO) -> some View {
        let current = inquiry.status ?? "submitted"
        let terminal = isTerminalStatus(current)
        Menu {
            menuStatusButton(inquiry, current: current, status: "contacted", title: LabeledCopy.contacted(language), icon: "paperplane.fill")
            menuStatusButton(inquiry, current: current, status: "reviewing", title: LabeledCopy.reviewing(language), icon: "clock.badge.checkmark")
            menuStatusButton(inquiry, current: current, status: "confirmed", title: LabeledCopy.confirm(language), icon: "checkmark.seal.fill")
            menuStatusButton(inquiry, current: current, status: "rescheduled", title: LabeledCopy.reschedule(language), icon: "calendar.badge.clock")
            menuStatusButton(inquiry, current: current, status: "completed", title: LabeledCopy.complete(language), icon: "flag.checkered")
            Divider()
            menuStatusButton(inquiry, current: current, status: "rejected", title: LabeledCopy.reject(language), icon: "xmark.seal.fill", destructive: true)
            menuStatusButton(inquiry, current: current, status: "closed", title: LabeledCopy.close(language), icon: "archivebox.fill", destructive: true)
        } label: {
            HStack(spacing: 8) {
                if updatingInquiryId == inquiry.id {
                    KXSpinner(size: 13, lineWidth: 1.8, tint: KXColor.accent)
                } else {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.black))
                }
                Text(LabeledCopy.updateStatus(language))
                    .font(.caption.weight(.black))
                Spacer(minLength: 0)
                Text(LabeledCopy.statusLabel(current, language))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusColor(current))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(KXColor.accent)
            .padding(.horizontal, 13)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(KXColor.accent.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(KXColor.accent.opacity(0.16), lineWidth: 0.7))
            .contentShape(Capsule())
        }
        .disabled(terminal || updatingInquiryId != nil)
        .opacity(terminal ? 0.55 : 1)
    }

    @ViewBuilder
    private func menuStatusButton(_ inquiry: KaiXListingInquiryDTO, current: String, status: String, title: String, icon: String, destructive: Bool = false) -> some View {
        Button(role: destructive ? .destructive : nil) {
            Task { await updateInquiry(inquiry, status: status) }
        } label: {
            Label(title, systemImage: icon)
        }
        .disabled(current == status)
    }

    private func typeChip(_ type: String) -> some View {
        Text(LabeledCopy.typeLabel(type, language))
            .font(.caption2.weight(.bold))
            .foregroundStyle(KXColor.accent)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(KXColor.accentSoft, in: Capsule())
    }

    private func statusChip(_ status: String) -> some View {
        Text(LabeledCopy.statusLabel(status, language))
            .font(.caption2.weight(.bold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(statusColor(status).opacity(0.12), in: Capsule())
    }

    private func actionButton(title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.black))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundStyle(filled ? .white : KXColor.accent)
                .background(filled ? KXColor.accent : KXColor.accent.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func statusAction(_ inquiry: KaiXListingInquiryDTO, status: String, title: String, icon: String) -> some View {
        let current = inquiry.status ?? "submitted"
        let disabled = updatingInquiryId != nil || current == status || ["rejected", "withdrawn", "completed", "closed", "spam", "reported"].contains(current)
        return Button {
            Task { await updateInquiry(inquiry, status: status) }
        } label: {
            HStack(spacing: 5) {
                if updatingInquiryId == inquiry.id {
                    KXSpinner(size: 12, lineWidth: 1.7, tint: statusColor(status))
                } else {
                    Image(systemName: icon)
                        .font(.caption2.weight(.black))
                }
                Text(title)
                    .font(.caption2.weight(.black))
            }
            .foregroundStyle(current == status ? .white : statusColor(status))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(current == status ? statusColor(status) : statusColor(status).opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled && current != status ? 0.5 : 1)
    }

    private func destructiveAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2.weight(.black))
                Text(title)
                    .font(.caption2.weight(.black))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.secondary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(updatingInquiryId != nil)
        .opacity(updatingInquiryId != nil ? 0.5 : 1)
    }

    @MainActor
    private func updateInquiry(_ inquiry: KaiXListingInquiryDTO, status: String) async {
        guard updatingInquiryId == nil else { return }
        updatingInquiryId = inquiry.id
        defer { updatingInquiryId = nil }
        do {
            let updated = try await KaiXAPIClient.shared.updateListingInquiry(inquiry.id, status: status)
            var items = itemsByRole[role] ?? []
            if let index = items.firstIndex(where: { $0.id == updated.id }) {
                items[index] = updated
            }
            itemsByRole[role] = items
            state = items.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    @MainActor
    private func deleteInquiry(_ inquiry: KaiXListingInquiryDTO) async {
        guard updatingInquiryId == nil else { return }
        updatingInquiryId = inquiry.id
        defer { updatingInquiryId = nil }
        do {
            let updated = try await KaiXAPIClient.shared.deleteListingInquiry(inquiry.id)
            var items = itemsByRole[role] ?? []
            if let index = items.firstIndex(where: { $0.id == updated.id }) {
                items[index] = updated
            }
            itemsByRole[role] = items
            state = items.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    private func openConversation(_ inquiry: KaiXListingInquiryDTO) {
        let conversationId = inquiry.resolvedConversationId
        if !conversationId.isEmpty {
            router.open(.conversation(conversationId: conversationId))
        } else {
            openListing(inquiry)
        }
    }

    private func openListing(_ inquiry: KaiXListingInquiryDTO) {
        let listingId = inquiry.resolvedListingId
        if !listingId.isEmpty {
            router.open(.cityListingDetail(listingId: listingId))
        }
    }

    private func normalizedDetails(_ inquiry: KaiXListingInquiryDTO) -> [(label: String, value: String)] {
        (inquiry.details ?? []).compactMap { item in
            let label = clean(item["label"] ?? item["name"])
            let value = clean(item["value"] ?? item["text"])
            guard !label.isEmpty, !value.isEmpty else { return nil }
            return (LabeledCopy.fieldLabel(label, language), LabeledCopy.fieldLabel(value, language))
        }
    }

    private func clean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formattedDate(_ raw: String) -> String {
        String(raw.prefix(10))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "submitted", "new": return KXColor.accent
        case "reviewing", "contacted", "rescheduled": return .orange
        case "confirmed", "completed": return .green
        case "rejected", "withdrawn", "closed", "spam", "reported": return .secondary
        default: return .secondary
        }
    }

    private func typeIcon(_ type: String) -> String {
        switch type {
        case "job_apply": return "briefcase.fill"
        case "rental_viewing", "rental_consult": return "house.fill"
        case "secondhand_trade_request", "secondhand_consult": return "bag.fill"
        case "restaurant_booking", "stay_booking", "travel_ticket_booking", "transfer_booking", "paperwork_booking", "moving_cleaning_booking", "life_setup_booking", "beauty_health_booking", "pet_family_booking", "service_booking":
            return "calendar.badge.clock"
        case "discount_claim", "discount_consult": return "ticket.fill"
        default: return "doc.text.fill"
        }
    }

    private func load(force: Bool = false) async {
        if !force, itemsByRole[role] != nil {
            state = (itemsByRole[role] ?? []).isEmpty ? .empty : .loaded
            return
        }
        if (itemsByRole[role] ?? []).isEmpty { state = .loading }
        guard KaiXBackend.token != nil else {
            state = .empty
            return
        }
        do {
            let items = try await KaiXAPIClient.shared.myListingInquiries(role: role.rawValue, bucket: bucket)
            itemsByRole[role] = items
            state = items.isEmpty ? .empty : .loaded
        } catch {
            state = (itemsByRole[role] ?? []).isEmpty ? .error(error.kaixUserMessage) : .loaded
        }
    }
}

private enum LabeledCopy {
    static func viewDetail(_ language: AppLanguage) -> String {
        pick(language, "查看详情", "詳細を見る", "View details")
    }

    static func followUpApplicant(_ language: AppLanguage) -> String {
        pick(language, "联系申请人", "応募者に連絡", "Message applicant")
    }

    static func followUpMessage(_ language: AppLanguage) -> String {
        pick(language, "补充沟通", "補足メッセージ", "Follow up")
    }

    static func reviewing(_ language: AppLanguage) -> String {
        pick(language, "处理中", "対応中", "Reviewing")
    }

    static func contacted(_ language: AppLanguage) -> String {
        pick(language, "已联系", "連絡済み", "Contacted")
    }

    static func confirm(_ language: AppLanguage) -> String {
        pick(language, "确认", "確定", "Confirm")
    }

    static func reschedule(_ language: AppLanguage) -> String {
        pick(language, "改期", "日程調整", "Reschedule")
    }

    static func reject(_ language: AppLanguage) -> String {
        pick(language, "拒绝", "却下", "Reject")
    }

    static func complete(_ language: AppLanguage) -> String {
        pick(language, "完成", "完了", "Complete")
    }

    static func close(_ language: AppLanguage) -> String {
        pick(language, "关闭", "終了", "Close")
    }

    static func withdraw(_ language: AppLanguage) -> String {
        pick(language, "撤回", "取り下げ", "Withdraw")
    }

    static func closeRecord(_ language: AppLanguage) -> String {
        pick(language, "关闭记录", "記録を閉じる", "Close record")
    }

    static func updateStatus(_ language: AppLanguage) -> String {
        pick(language, "更新进度", "進捗を更新", "Update status")
    }

    /// A short, human hint that says what this status means and what to do
    /// next — so the manager reads like guidance, not jargon.
    static func statusHint(_ status: String, isReceived: Bool, language: AppLanguage) -> String? {
        switch status {
        case "submitted", "new":
            return isReceived
                ? pick(language, "新咨询，建议尽快联系对方", "新しい問い合わせ。早めに連絡しましょう", "New inquiry — reach out soon")
                : pick(language, "已发送，等待对方回应", "送信済み。相手の返信待ちです", "Sent — waiting for a reply")
        case "reviewing":
            return pick(language, "你正在处理这条咨询", "対応中の問い合わせです", "You're handling this inquiry")
        case "contacted":
            return isReceived
                ? pick(language, "已联系对方，等待回应", "連絡済み。返信を待っています", "Contacted — awaiting their reply")
                : pick(language, "对方已联系你", "相手から連絡がありました", "They've reached out to you")
        case "confirmed":
            return pick(language, "已确认，准备完成交易或服务", "確定済み。取引・サービスへ進みましょう", "Confirmed — ready to proceed")
        case "rescheduled":
            return pick(language, "正在协调新的时间", "日程を調整しています", "Coordinating a new time")
        case "completed":
            return pick(language, "这条咨询已顺利完成", "この問い合わせは完了しました", "This inquiry is complete")
        case "rejected":
            return pick(language, "已拒绝该咨询", "この問い合わせは却下されました", "This inquiry was declined")
        case "withdrawn":
            return pick(language, "咨询已撤回", "問い合わせは取り下げられました", "This inquiry was withdrawn")
        case "closed":
            return pick(language, "记录已关闭", "記録は終了しました", "Record closed")
        case "spam", "reported":
            return pick(language, "已标记并处理", "報告・対応済みです", "Flagged and handled")
        default:
            return nil
        }
    }

    static func applicant(_ name: String, _ language: AppLanguage) -> String {
        switch language {
        case .ja: return "応募者 \(name)"
        case .en: return "Applicant \(name)"
        default: return "申请人 \(name)"
        }
    }

    static func counterpart(_ name: String, _ language: AppLanguage) -> String {
        switch language {
        case .ja: return "相手 \(name)"
        case .en: return "Contact \(name)"
        default: return "对方 \(name)"
        }
    }

    static func typeLabel(_ type: String, _ language: AppLanguage) -> String {
        switch type {
        case "secondhand_trade_request", "secondhand_consult":
            pick(language, "二手交易", "フリマ取引", "Marketplace")
        case "rental_viewing", "rental_consult":
            pick(language, "租房看房", "内見・賃貸", "Rental viewing")
        case "rental_application":
            pick(language, "租房申请", "賃貸申込", "Rental application")
        case "job_apply":
            pick(language, "应聘", "求人応募", "Job application")
        case "restaurant_booking":
            pick(language, "餐厅预约", "飲食予約", "Restaurant booking")
        case "stay_booking":
            pick(language, "住宿预约", "宿泊予約", "Stay booking")
        case "travel_ticket_booking":
            pick(language, "票务行程", "旅行・チケット", "Travel/tickets")
        case "transfer_booking":
            pick(language, "接送预约", "送迎予約", "Transfer")
        case "paperwork_booking":
            pick(language, "手续协助", "手続きサポート", "Paperwork")
        case "moving_cleaning_booking":
            pick(language, "搬家清洁", "引越し・清掃", "Moving/cleaning")
        case "life_setup_booking":
            pick(language, "生活开通", "生活セットアップ", "Life setup")
        case "beauty_health_booking":
            pick(language, "美容健康", "美容・健康", "Beauty/health")
        case "pet_family_booking":
            pick(language, "宠物家庭", "ペット・家庭", "Pet/family")
        case "service_booking":
            pick(language, "服务预约", "サービス予約", "Service booking")
        case "discount_claim", "discount_consult":
            pick(language, "优惠领取", "特典問い合わせ", "Deal inquiry")
        default:
            L("inquiryGeneral", language)
        }
    }

    static func statusLabel(_ status: String, _ language: AppLanguage) -> String {
        switch status {
        case "submitted", "new":
            pick(language, "新提交", "新規送信", "New")
        case "reviewing":
            pick(language, "处理中", "対応中", "Reviewing")
        case "contacted":
            pick(language, "已联系", "連絡済み", "Contacted")
        case "confirmed":
            pick(language, "已确认", "確定済み", "Confirmed")
        case "rescheduled":
            pick(language, "待改期", "日程調整中", "Rescheduling")
        case "rejected":
            pick(language, "已拒绝", "却下", "Rejected")
        case "withdrawn":
            pick(language, "已撤回", "取り下げ", "Withdrawn")
        case "completed":
            pick(language, "已完成", "完了", "Completed")
        case "closed":
            pick(language, "已关闭", "終了", "Closed")
        case "spam":
            pick(language, "已屏蔽", "ブロック済み", "Blocked")
        case "reported":
            pick(language, "已举报", "報告済み", "Reported")
        default:
            status.isEmpty ? pick(language, "已提交", "送信済み", "Submitted") : status
        }
    }

    static func fieldLabel(_ value: String, _ language: AppLanguage) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return value }
        if let entry = fieldTable[normalized] {
            return pick(language, normalized, entry.ja, entry.en)
        }
        return KXListingCopy.attributeLabel(normalized, language)
    }

    private static func pick(_ language: AppLanguage, _ zh: String, _ ja: String, _ en: String) -> String {
        switch language {
        case .ja: return ja
        case .en: return en
        default: return zh
        }
    }

    private static let fieldTable: [String: (ja: String, en: String)] = [
        "希望看房日期": ("希望内見日", "Preferred viewing date"),
        "希望时段": ("希望時間帯", "Preferred time"),
        "当前情况": ("現在の状況", "Current situation"),
        "入住人数": ("入居人数", "Residents"),
        "预算": ("予算", "Budget"),
        "联系方式": ("連絡先", "Contact"),
        "姓名": ("氏名", "Name"),
        "签证状态": ("在留資格", "Visa status"),
        "日语水平": ("日本語レベル", "Japanese level"),
        "可工作时间": ("勤務可能時間", "Availability"),
        "最快入职时间": ("最短開始日", "Earliest start"),
        "自我介绍": ("自己紹介", "Self introduction"),
        "咨询意向": ("相談内容", "Intent"),
        "希望交易地点": ("希望受け渡し場所", "Preferred meetup"),
        "可交易时间": ("取引可能時間", "Available time"),
        "交易方式": ("取引方法", "Trade method"),
        "补充留言": ("追加メッセージ", "Additional message"),
        "用餐日期": ("来店日", "Dining date"),
        "到店时间": ("来店時間", "Arrival time"),
        "用餐人数": ("人数", "Party size"),
        "预订姓名": ("予約名", "Booking name"),
        "特殊需求": ("特別リクエスト", "Special requests"),
        "入住日期": ("チェックイン", "Check-in"),
        "退房日期": ("チェックアウト", "Check-out"),
        "房间数": ("部屋数", "Rooms"),
        "补充说明": ("補足", "Notes"),
        "出行日期": ("利用日", "Travel date"),
        "人数 / 票数": ("人数 / 枚数", "People / tickets"),
        "希望语言": ("希望言語", "Preferred language"),
        "用车日期": ("利用日", "Ride date"),
        "路线": ("ルート", "Route"),
        "航班/车次": ("便名 / 到着時間", "Flight / train"),
        "行李数": ("荷物数", "Luggage"),
        "具体需求": ("具体的な依頼内容", "Request details"),
        "事项类型": ("手続き種別", "Procedure type"),
        "希望完成时间": ("希望納期", "Preferred deadline"),
        "物品/房间说明": ("荷物・部屋について", "Items / room notes"),
        "希望日期": ("希望日", "Preferred date"),
        "服务区域": ("対応エリア", "Service area"),
        "物品量/房型": ("荷物量・間取り", "Item volume / room type"),
        "服务事项": ("サービス内容", "Service item"),
        "注意事项": ("注意事項", "Notes"),
        "预约日期": ("予約日", "Appointment date"),
        "预约时段": ("予約時間帯", "Appointment time"),
        "服务项目": ("サービス項目", "Service item")
    ]
}

/// Membership payment history — mirrors the Web 工作台 订单 screen.
struct MyOrdersView: View {
    @Environment(\.appLanguage) private var language

    @State private var orders: [KaiXPaymentOrderDTO] = []
    @State private var state: ScreenState = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                KXInlineLoader().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ErrorStateView(message: message) { Task { await load() } }
            case .empty:
                EmptyStateView(
                    title: L("ordersEmpty", language),
                    subtitle: L("ordersEmptyHelp", language),
                    systemImage: "doc.plaintext"
                )
            case .loaded:
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(orders) { order in
                            row(order)
                        }
                    }
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
                    .padding(.top, 10)
                    .kxTabBarSafeBottomPadding()
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle(L("ordersTitle", language))
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .task { await load() }
    }

    private func row(_ order: KaiXPaymentOrderDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(order.plan_key?.isEmpty == false ? L("membershipSettingsTitle", language) : order.order_no)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    statusChip(order.status ?? "pending")
                    if let provider = order.provider, !provider.isEmpty {
                        Text(providerLabel(provider))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let created = order.created_at, !created.isEmpty {
                        Text(String(created.prefix(10)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(amountLabel(order))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private func amountLabel(_ order: KaiXPaymentOrderDTO) -> String {
        let amount = order.amount ?? 0
        let currency = (order.currency ?? "CNY").uppercased()
        let symbol = currency == "JPY" ? "¥" : (currency == "USD" ? "$" : "¥")
        return "\(symbol)\(String(format: amount.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.2f", amount))"
    }

    private func providerLabel(_ provider: String) -> String {
        switch provider {
        case "apple_iap": "App Store"
        case "wechat": "微信支付"
        case "alipay": "支付宝"
        default: provider
        }
    }

    private func statusChip(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "paid": (L("orderPaid", language), .green)
        case "pending": (L("orderPending", language), .orange)
        case "failed": (L("orderFailed", language), .red)
        case "refunded": (L("orderRefunded", language), .secondary)
        case "expired", "cancelled": (L("orderClosed", language), .secondary)
        default: (status, .secondary)
        }
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func load() async {
        if orders.isEmpty { state = .loading }
        guard KaiXBackend.token != nil else {
            state = .empty
            return
        }
        do {
            orders = try await KaiXAPIClient.shared.membershipOrders()
            state = orders.isEmpty ? .empty : .loaded
        } catch {
            state = orders.isEmpty ? .error(error.kaixUserMessage) : .loaded
        }
    }
}
