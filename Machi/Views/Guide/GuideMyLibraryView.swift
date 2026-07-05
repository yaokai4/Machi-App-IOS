import SwiftUI

/// 我的资料库 — the post-purchase home for everything a user owns inside Guide:
/// purchased + member-unlocked materials, their service requests, and a merged
/// order history. Mirrors the web `/guide/my-library` page and reads the same
/// `/api/guide/my-library` endpoint. Read-only: each material links to its
/// product page, which gates the actual download.
struct GuideMyLibraryView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    private enum Tab: Hashable { case materials, services, orders }

    @State private var tab: Tab = .materials
    @State private var library: KaiXGuideLibraryResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var materials: [KaiXGuideLibraryMaterial] { library?.materials ?? [] }
    private var services: [KaiXGuideLibraryService] { library?.services ?? [] }
    private var orders: [KaiXGuideLibraryOrder] { library?.orders ?? [] }

    private var languageCode: String {
        switch language {
        case .ja: return "ja"
        case .en: return "en"
        case .zh, .system: return "zh-CN"
        }
    }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                    segmentBar
                    content
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideText(language, "我的资料库", "マイ資料庫", "My library"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(alignment: .top, spacing: KXSpacing.md) {
                    GuideIconBubble(icon: "books.vertical.fill", color: KXColor.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(guideText(language, "我的资料库", "マイ資料庫", "My library"))
                            .font(.title2.weight(.bold))
                        Text(guideText(language,
                                       "购买和会员解锁的资料、我的服务申请、订单记录都在这里。",
                                       "購入・会員解放した資料、サービス申請、注文履歴をここにまとめています。",
                                       "Purchased and member-unlocked resources, your service requests, and orders — all in one place."))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if library?.isMember == true {
                    GuideBadge(guideText(language, "Machi 认证会员", "Machi 認証会員", "Verified member"), tint: KXColor.accent)
                }
            }
        }
    }

    // MARK: Segment bar

    private var segmentBar: some View {
        HStack(spacing: KXSpacing.sm) {
            segment(.materials, guideText(language, "我的资料", "資料", "Resources"), materials.count)
            segment(.services, guideText(language, "我的服务", "サービス", "Services"), services.count)
            segment(.orders, guideText(language, "我的订单", "注文", "Orders"), orders.count)
        }
    }

    private func segment(_ value: Tab, _ title: String, _ count: Int) -> some View {
        let selected = tab == value
        return Button {
            tab = value
        } label: {
            Text(count > 0 ? "\(title) \(count)" : title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selected ? KXColor.accent : KXColor.livingSurface.opacity(0.7),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LoadingView()
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) {
                Task { await load() }
            }
        } else {
            switch tab {
            case .materials: materialsList
            case .services: servicesList
            case .orders: ordersList
            }
        }
    }

    @ViewBuilder
    private var materialsList: some View {
        if materials.isEmpty {
            EmptyStateView(
                title: guideText(language, "还没有资料", "資料はまだありません", "No resources yet"),
                subtitle: guideText(language, "购买资料或开通会员后，会在这里集中收藏。", "資料を購入するか会員になると、ここに集まります。", "Buy a resource or become a member and it shows up here."),
                systemImage: "doc.text"
            )
        } else {
            LazyVStack(spacing: 10) {
                ForEach(materials) { item in
                    Button {
                        if let slug = item.slug, !slug.isEmpty {
                            router.open(.guideProduct(slug: slug))
                        }
                    } label: {
                        GuideLibraryMaterialRow(material: item, language: language)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var servicesList: some View {
        if services.isEmpty {
            EmptyStateView(
                title: guideText(language, "还没有服务", "サービスはまだありません", "No services yet"),
                subtitle: guideText(language, "申请资料代写、咨询等服务后，会在这里跟踪进度。", "代行・相談などのサービスを申請すると、ここで進捗を確認できます。", "Request a service and track its progress here."),
                systemImage: "bag"
            )
        } else {
            LazyVStack(spacing: 10) {
                ForEach(services) { item in
                    GuideLibraryServiceRow(service: item, language: language)
                }
            }
        }
    }

    @ViewBuilder
    private var ordersList: some View {
        if orders.isEmpty {
            EmptyStateView(
                title: guideText(language, "还没有订单", "注文はまだありません", "No orders yet"),
                subtitle: guideText(language, "购买资料或充值后，订单会显示在这里。", "資料の購入やチャージ後、注文がここに表示されます。", "Purchases and top-ups appear here."),
                systemImage: "receipt"
            )
        } else {
            LazyVStack(spacing: 10) {
                ForEach(orders) { item in
                    GuideLibraryOrderRow(order: item, language: language)
                }
            }
        }
    }

    // MARK: Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            library = try await KaiXAPIClient.shared.guideMyLibrary(language: languageCode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Rows

private struct GuideLibraryMaterialRow: View {
    let material: KaiXGuideLibraryMaterial
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: "doc.text.fill")
                .kxScaledFont(17, weight: .bold)
                .foregroundStyle(KXColor.accent)
                .frame(width: 40, height: 40)
                .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                HStack(spacing: 6) {
                    Text(material.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if material.isMemberUnlocked {
                        GuideBadge(guideText(language, "会员解锁", "会員解放", "Member"), tint: KXColor.accent)
                    } else {
                        GuideBadge(guideText(language, "已购买", "購入済み", "Owned"), tint: .green)
                    }
                }
                if let subtitle = material.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.livingSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8))
        .contentShape(Rectangle())
    }
}

private struct GuideLibraryServiceRow: View {
    let service: KaiXGuideLibraryService
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: "bag.fill")
                .kxScaledFont(17, weight: .bold)
                .foregroundStyle(.purple)
                .frame(width: 40, height: 40)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text(service.productTitle?.isEmpty == false ? service.productTitle! : guideText(language, "资料服务", "資料サービス", "Service"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let created = service.createdAt, !created.isEmpty {
                    Text(String(created.prefix(10)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            GuideBadge(serviceStatusLabel, tint: serviceStatusTint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.livingSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8))
    }

    private var serviceStatusLabel: String {
        switch service.status ?? "pending" {
        case "completed", "fulfilled", "done": return guideText(language, "已完成", "完了", "Done")
        case "in_progress", "processing", "accepted": return guideText(language, "进行中", "対応中", "In progress")
        case "cancelled", "rejected": return guideText(language, "已取消", "キャンセル", "Cancelled")
        default: return guideText(language, "待处理", "受付中", "Pending")
        }
    }

    private var serviceStatusTint: Color {
        switch service.status ?? "pending" {
        case "completed", "fulfilled", "done": return .green
        case "in_progress", "processing", "accepted": return KXColor.accent
        case "cancelled", "rejected": return .secondary
        default: return .orange
        }
    }
}

private struct GuideLibraryOrderRow: View {
    let order: KaiXGuideLibraryOrder
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: order.isTopUp ? "creditcard.fill" : "doc.text.fill")
                .kxScaledFont(17, weight: .bold)
                .foregroundStyle(order.isTopUp ? Color.orange : KXColor.accent)
                .frame(width: 40, height: 40)
                .background((order.isTopUp ? Color.orange : KXColor.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text(order.title?.isEmpty == false ? order.title! : guideText(language, "订单", "注文", "Order"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let created = order.createdAt, !created.isEmpty {
                    Text(String(created.prefix(10)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: KXSpacing.xs) {
                Text(amountLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                GuideBadge(statusLabel, tint: statusTint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.livingSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8))
    }

    private var amountLabel: String {
        let points = order.pricePoints ?? 0
        if points > 0 {
            return "\(points) " + guideText(language, "币", "コイン", "pts")
        }
        let amount = order.amount ?? 0
        if order.isTopUp {
            // top-up amount is stored in minor units (cents)
            let major = Double(amount) / 100.0
            return currencySymbol + String(format: "%.2f", major)
        }
        return currencySymbol + "\(amount)"
    }

    private var currencySymbol: String {
        switch (order.currency ?? "CNY").uppercased() {
        case "JPY": return "¥"
        case "USD": return "$"
        case "CNY", "RMB": return "¥"
        default: return ((order.currency ?? "") + " ")
        }
    }

    private var statusLabel: String {
        switch order.status ?? "" {
        case "paid", "fulfilled", "succeeded", "completed": return guideText(language, "已支付", "支払済み", "Paid")
        case "pending", "created": return guideText(language, "待支付", "未払い", "Pending")
        case "refunded": return guideText(language, "已退款", "返金済み", "Refunded")
        default: return order.status ?? guideText(language, "订单", "注文", "Order")
        }
    }

    private var statusTint: Color {
        switch order.status ?? "" {
        case "paid", "fulfilled", "succeeded", "completed": return .green
        case "pending", "created": return .orange
        case "refunded": return .secondary
        default: return .secondary
        }
    }
}
