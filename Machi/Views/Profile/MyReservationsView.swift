import SwiftUI

/// "我的预约" — the reservations I made as a customer (看房 / 到店 / 服务预约).
/// Slot-based, no money. Backed by GET /api/my/reservations; cancel via
/// POST /api/reservations/:id/cancel. Distinct from MyInquiriesView (inquiry
/// leads) — this is the time-slot calendar side.
struct MyReservationsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    @State private var items: [KaiXBookingDTO] = []
    @State private var state: ScreenState = .idle
    @State private var cancellingId: String?

    var body: some View {
        content
            .navigationTitle(KXListingCopy.pickText(language, "我的预约", "予約", "My reservations"))
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
            EmptyStateView(
                title: KXListingCopy.pickText(language, "还没有预约", "予約はまだありません", "No reservations yet"),
                subtitle: KXListingCopy.pickText(language, "在房源、餐厅或服务详情里选择时段即可预约。", "物件・飲食店・サービスの詳細で枠を選んで予約できます。", "Pick a slot on a listing to book."),
                systemImage: "calendar"
            )
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(items) { booking in
                        row(booking)
                    }
                }
                .padding(KXSpacing.screen)
            }
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
            .kxLivingSurface(radius: 18)
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
