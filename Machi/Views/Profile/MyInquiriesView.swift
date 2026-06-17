import SwiftUI

/// Workbench inquiries manager — mirrors the Web 工作台 咨询 screen.
/// 收到: people contacting MY listings (buyer leads, job applications,
/// bookings). 发出: inquiries I sent to others. The record is the source of
/// truth; chat is only a follow-up channel.
struct MyInquiriesView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    let currentUser: UserEntity

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

    var body: some View {
        VStack(spacing: 0) {
            KXSegmentedControl(Role.allCases, selection: $role) { item in
                Text(item.title(language))
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.vertical, 10)

            content
        }
        .navigationTitle(L("inquiriesTitle", language))
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
        let counterpart = role == .received ? inquiry.from_user : inquiry.to_user
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
                            Text(role == .received ? "申请人 \(name)" : "对方 \(name)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let created = inquiry.created_at, !created.isEmpty {
                            Text(formattedDate(created))
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

            HStack(spacing: 8) {
                actionButton(title: "查看详情", icon: "doc.text.magnifyingglass", filled: false) {
                    openListing(inquiry)
                }
                actionButton(title: role == .received ? "联系申请人" : "打开私信", icon: "bubble.left.and.bubble.right.fill", filled: true) {
                    openConversation(inquiry)
                }
            }
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private func typeChip(_ type: String) -> some View {
        let label: String = switch type {
        case "secondhand_trade_request", "secondhand_consult": "二手交易"
        case "rental_viewing", "rental_consult": "租房看房"
        case "job_apply": "应聘"
        case "restaurant_booking": "餐厅预约"
        case "stay_booking": "住宿预约"
        case "travel_ticket_booking": "票务行程"
        case "transfer_booking": "接送预约"
        case "paperwork_booking": "手续翻译"
        case "moving_cleaning_booking": "搬家清洁"
        case "life_setup_booking": "生活开通"
        case "beauty_health_booking": "美容健康"
        case "pet_family_booking": "宠物家庭"
        case "service_booking": "服务预约"
        case "discount_claim", "discount_consult": "优惠领取"
        default: L("inquiryGeneral", language)
        }
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(KXColor.accent)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(KXColor.accentSoft, in: Capsule())
    }

    private func statusChip(_ status: String) -> some View {
        Text(statusLabel(status))
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

    private func openConversation(_ inquiry: KaiXListingInquiryDTO) {
        if let conversationId = inquiry.conversation_id, !conversationId.isEmpty {
            router.open(.conversation(conversationId: conversationId))
        } else {
            openListing(inquiry)
        }
    }

    private func openListing(_ inquiry: KaiXListingInquiryDTO) {
        if let listingId = inquiry.listing_id, !listingId.isEmpty {
            router.open(.cityListingDetail(listingId: listingId))
        }
    }

    private func normalizedDetails(_ inquiry: KaiXListingInquiryDTO) -> [(label: String, value: String)] {
        (inquiry.details ?? []).compactMap { item in
            let label = clean(item["label"] ?? item["name"])
            let value = clean(item["value"] ?? item["text"])
            guard !label.isEmpty, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    private func clean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formattedDate(_ raw: String) -> String {
        String(raw.prefix(10))
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "submitted", "new": "新提交"
        case "reviewing": "处理中"
        case "contacted": "已联系"
        case "confirmed": "已确认"
        case "rescheduled": "待改期"
        case "rejected": "已拒绝"
        case "withdrawn": "已撤回"
        case "completed": "已完成"
        case "closed": "已关闭"
        case "spam": "已屏蔽"
        case "reported": "已举报"
        default: status.isEmpty ? "已提交" : status
        }
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
            let items = try await KaiXAPIClient.shared.myListingInquiries(role: role.rawValue)
            itemsByRole[role] = items
            state = items.isEmpty ? .empty : .loaded
        } catch {
            state = (itemsByRole[role] ?? []).isEmpty ? .error(error.kaixUserMessage) : .loaded
        }
    }
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
