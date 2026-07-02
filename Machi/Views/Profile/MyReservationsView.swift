import SwiftUI

/// "我的预约" — the reservations I made as a customer (看房 / 到店 / 服务预约).
/// Slot-based, no money. Backed by GET /api/my/reservations; cancel via
/// POST /api/reservations/:id/cancel. Distinct from MyInquiriesView (inquiry
/// leads) — this is the time-slot calendar side.
struct MyReservationsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    /// When embedded in the 我的预约 hub, suppress the standalone nav title.
    var embedded: Bool = false

    @State private var items: [KaiXBookingDTO] = []
    @State private var state: ScreenState = .idle
    @State private var cancellingId: String?

    var body: some View {
        content
            .navigationTitle(embedded ? "" : KXListingCopy.pickText(language, "我的预约", "予約", "My reservations"))
            .navigationBarTitleDisplayMode(.inline)
            .kxPageBackground()
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingView()
        case .error(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .empty:
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 96)
                    KXEmptyActionPanel(
                        icon: "calendar.badge.clock",
                        tint: KXColor.accent,
                        title: KXListingCopy.pickText(language, "还没有预约", "予約はまだありません", "No reservations yet"),
                        subtitle: KXListingCopy.pickText(language, "看房、到店和服务预约会按时间排在这里，方便你确认下一次要去哪里。", "内見・来店・サービス予約が時間順にここへ表示されます。", "Viewing, visit, and service bookings appear here in time order."),
                        actionTitle: KXListingCopy.pickText(language, "去发现可预约服务", "予約できるサービスを見る", "Find bookable services")
                    ) {
                        router.open(.search(initialQuery: KXListingCopy.pickText(language, "预约", "予約", "booking")), in: .search)
                    }
                    Spacer(minLength: 180)
                }
                .padding(KXSpacing.screen)
            }
            .kxReadableWidth()
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(items) { booking in
                        row(booking)
                    }
                }
                .padding(KXSpacing.screen)
            }
            .refreshable { await load() }
            .kxReadableWidth()
        }
    }

    private func row(_ booking: KaiXBookingDTO) -> some View {
        let cancelled = (booking.status ?? "confirmed") == "cancelled"
        let isPast = (booking.startDate ?? .distantFuture) < Date()
        return Button {
            if let lid = booking.listingId, !lid.isEmpty {
                router.open(.cityListingDetail(listingId: lid))
            }
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(dayNumber(booking.startDate))
                        .font(.title3.weight(.black))
                    Text(monthLabel(booking.startDate))
                        .font(.caption2.weight(.bold))
                }
                .frame(width: 52, height: 56)
                .foregroundStyle(cancelled ? Color.secondary : KXColor.accent)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill((cancelled ? Color.secondary : KXColor.accent).opacity(0.12))
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.listingTitle ?? KXListingCopy.pickText(language, "预约", "予約", "Reservation"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.livingInk)
                        .lineLimit(1)
                        .strikethrough(cancelled)
                    Text(fullDateTime(booking.startDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    statusChip(cancelled: cancelled, isPast: isPast)
                }
                Spacer()
                if !cancelled && !isPast {
                    if cancellingId == booking.id {
                        KXSpinner(size: 18, lineWidth: 2)
                    } else {
                        Button {
                            Task { await cancel(booking) }
                        } label: {
                            Text(KXListingCopy.pickText(language, "取消", "取消", "Cancel"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KXColor.livingWarm)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(KXColor.livingWarm.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(KXSpacing.md)
            .kxLivingSurface(radius: KXRadius.lg)
            .opacity(cancelled ? 0.6 : 1)
        }
        .buttonStyle(KXPressableStyle())
    }

    private func statusChip(cancelled: Bool, isPast: Bool) -> some View {
        let (text, color): (String, Color) = cancelled
            ? (KXListingCopy.pickText(language, "已取消", "キャンセル済み", "Cancelled"), .secondary)
            : isPast
                ? (KXListingCopy.pickText(language, "已结束", "終了", "Past"), .secondary)
                : (KXListingCopy.pickText(language, "已确认", "確定", "Confirmed"), KXColor.accent)
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - Data

    private func load() async {
        if items.isEmpty { state = .loading }
        do {
            let result = try await KaiXAPIClient.shared.myReservations()
            await MainActor.run {
                items = result
                state = result.isEmpty ? .empty : .loaded
            }
        } catch {
            await MainActor.run {
                state = items.isEmpty ? .error(KXListingCopy.pickText(language, "加载失败，请重试", "読み込みに失敗しました", "Failed to load")) : .loaded
            }
        }
    }

    private func cancel(_ booking: KaiXBookingDTO) async {
        await MainActor.run { cancellingId = booking.id }
        do {
            try await KaiXAPIClient.shared.cancelReservation(booking.id)
            await load()
        } catch {
            // leave the row as-is; a reload will reflect server truth next time
        }
        await MainActor.run { cancellingId = nil }
    }

    // MARK: - Formatting

    private func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        switch language {
        case .ja: f.locale = Locale(identifier: "ja_JP")
        case .en: f.locale = Locale(identifier: "en_US")
        default: f.locale = Locale(identifier: "zh_CN")
        }
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private func dayNumber(_ date: Date?) -> String { guard let date else { return "—" }; return formatter("d").string(from: date) }
    private func monthLabel(_ date: Date?) -> String { guard let date else { return "" }; return formatter("MMM").string(from: date) }
    private func fullDateTime(_ date: Date?) -> String { guard let date else { return "" }; return formatter("EEEMMMdHm").string(from: date) }
}

/// "我的预约" hub — one place for every booking I made, regardless of mechanism:
/// • 已约时段 = confirmed slot bookings (time-slot calendar)
/// • 预约请求 = intake-form reservations (看房 / 订座 / 服务预约) with their status
/// Keeps all reservations together instead of scattering them across 咨询/预约.
struct MyReservationsHubView: View {
    @Environment(\.appLanguage) private var language
    let currentUser: UserEntity

    private enum Tab: String, CaseIterable, Identifiable {
        case slots, requests
        var id: String { rawValue }
        func title(_ language: AppLanguage) -> String {
            switch self {
            case .slots: KXListingCopy.pickText(language, "已约时段", "予約済み枠", "Booked slots")
            case .requests: KXListingCopy.pickText(language, "预约请求", "予約リクエスト", "Requests")
            }
        }
    }

    @State private var tab: Tab = .slots

    var body: some View {
        VStack(spacing: 0) {
            KXSegmentedControl(Tab.allCases, selection: $tab) { item in
                Text(item.title(language))
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.vertical, 10)

            switch tab {
            case .slots:
                MyReservationsView(embedded: true)
            case .requests:
                MyInquiriesView(currentUser: currentUser, bucket: "reservation", embedded: true)
            }
        }
        .navigationTitle(KXListingCopy.pickText(language, "我的预约", "予約", "My reservations"))
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
    }
}

/// "时段预约" — host-side slot management entry. Lists the listings that accept
/// online bookings (租房 / 本地服务) so the owner can jump in and set or edit
/// their bookable time slots (the per-listing slot editor lives on the detail
/// page). Makes slot configuration discoverable instead of buried.
struct MySlotManagerListView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    let currentUser: UserEntity

    @State private var listings: [KaiXCityListingDTO] = []
    @State private var state: ScreenState = .idle

    private static let bookableTypes = ["rental", "local_service"]

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                KXInlineLoader().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ErrorStateView(message: message) { Task { await load() } }
            case .empty:
                ScrollView {
                    VStack(spacing: 16) {
                        Spacer(minLength: 96)
                        KXEmptyActionPanel(
                            icon: "calendar.badge.plus",
                            tint: KXColor.accent,
                            title: KXListingCopy.pickText(language, "暂无可约时段的发布", "予約枠を設定できる投稿がありません", "No bookable listings yet"),
                            subtitle: KXListingCopy.pickText(language, "发布租房或本地服务后,就能在详情页设置可预约时段,让对方在线选时间。", "賃貸やローカルサービスを投稿すると、詳細ページで予約枠を設定できます。", "Publish a rental or local service, then set bookable slots on its detail page."),
                            actionTitle: KXListingCopy.pickText(language, "去发布服务", "サービスを投稿", "Publish a service")
                        ) {
                            router.open(.createCityListing(type: "local_service", citySlug: nil))
                        }
                        Spacer(minLength: 180)
                    }
                    .padding(KXSpacing.screen)
                }
                .kxReadableWidth()
            case .loaded:
                ScrollView {
                    LazyVStack(spacing: 10) {
                        Text(KXListingCopy.pickText(language, "选择一条发布,进入详情即可添加 / 删除可预约时段。", "投稿を選ぶと、詳細で予約枠を追加・削除できます。", "Pick a listing to add or remove its bookable slots on the detail page."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 2)
                        ForEach(listings) { listing in
                            Button {
                                router.open(.cityListingDetail(listingId: listing.id))
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: listing.type == "rental" ? "house.fill" : "storefront.fill")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(KXColor.accent)
                                        .frame(width: 38, height: 38)
                                        .background(KXColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(listing.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                        Text(KXListingCopy.pickText(language, "管理可预约时段", "予約枠を管理", "Manage slots"))
                                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "calendar.badge.clock").font(.subheadline).foregroundStyle(.tertiary)
                                }
                                .padding(14)
                                .kxGlassSurface(radius: KXRadius.lg)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
                    .padding(.top, 10)
                    .kxTabBarSafeBottomPadding()
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle(KXListingCopy.pickText(language, "时段预约", "予約枠管理", "Booking slots"))
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .task { await load() }
    }

    private func load() async {
        if listings.isEmpty { state = .loading }
        guard KaiXBackend.token != nil else { state = .empty; return }
        do {
            let results = try await withThrowingTaskGroup(of: [KaiXCityListingDTO].self) { group in
                for type in Self.bookableTypes {
                    group.addTask { try await KaiXAPIClient.shared.myListings(type: type) }
                }
                var merged: [KaiXCityListingDTO] = []
                for try await page in group { merged.append(contentsOf: page) }
                return merged
            }
            var seen = Set<String>()
            listings = results
                .filter { $0.status != "sold" && seen.insert($0.id).inserted }
                .sorted { ($0.updated_at ?? $0.updatedAt ?? "") > ($1.updated_at ?? $1.updatedAt ?? "") }
            state = listings.isEmpty ? .empty : .loaded
        } catch {
            state = listings.isEmpty ? .error(error.kaixUserMessage) : .loaded
        }
    }
}

private struct KXEmptyActionPanel: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 7) {
                Text(title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(KXColor.livingInk)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button(action: action) {
                Label(actionTitle, systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(tint, in: Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 32)
        .kxLivingSurface(radius: KXRadius.sheet, elevated: true)
    }
}
