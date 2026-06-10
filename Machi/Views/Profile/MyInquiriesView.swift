import SwiftUI

/// Workbench inquiries manager — mirrors the Web 工作台 咨询 screen.
/// 收到: people contacting MY listings (buyer leads, job applications,
/// bookings). 发出: inquiries I sent to others. Rows open the seeded
/// conversation so the follow-up happens in chat.
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
                    Button {
                        open(inquiry)
                    } label: {
                        row(inquiry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.vertical, 10)
        }
        .refreshable { await load(force: true) }
    }

    private func row(_ inquiry: KaiXListingInquiryDTO) -> some View {
        let counterpart = role == .received ? inquiry.from_user : inquiry.to_user
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(inquiry.listing?.title ?? L("inquiryListingGone", language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    typeChip(inquiry.type ?? "general")
                }
                if let message = inquiry.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let name = counterpart?.display_name ?? counterpart?.displayName, !name.isEmpty {
                        Text(name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let created = inquiry.created_at, !created.isEmpty {
                        Text(String(created.prefix(10)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.subheadline)
                .foregroundStyle(KXColor.accent.opacity(0.8))
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
        .contentShape(Rectangle())
    }

    private func typeChip(_ type: String) -> some View {
        let label: String = switch type {
        case "secondhand_consult": "二手"
        case "rental_consult": "租房"
        case "job_apply": "应聘"
        case "service_booking": "预约"
        case "discount_consult": "优惠"
        default: L("inquiryGeneral", language)
        }
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(KXColor.accent)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(KXColor.accentSoft, in: Capsule())
    }

    private func open(_ inquiry: KaiXListingInquiryDTO) {
        if let conversationId = inquiry.conversation_id, !conversationId.isEmpty {
            router.open(.conversation(conversationId: conversationId))
        } else if let listingId = inquiry.listing_id, !listingId.isEmpty {
            router.open(.cityListingDetail(listingId: listingId))
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
                    .padding(.vertical, 10)
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
