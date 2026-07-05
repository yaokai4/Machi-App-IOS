import AVKit
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Listing detail screen + its booking section, inquiry/intake sheets, and
// publish-success sheet — extracted from DiscoverView.swift. Reached via
// KXRoute.cityListingDetail; navigation back to channel/list is by route.

/// Reservation calendar on a listing detail (no money): a horizontal day strip
/// plus time-slot chips the merchant/landlord published. Renders nothing until
/// slots load and stays hidden when none exist, so it only appears where the
/// owner actually opened bookings (看房 / 餐厅订座 / 服务预约).
struct ListingBookingSection: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let listingId: String
    let listingType: String?

    @State private var slots: [KaiXBookingSlotDTO] = []
    @State private var loaded = false
    @State private var isOwner = false
    @State private var selectedDayKey: String?
    @State private var inFlightSlotId: String?
    @State private var bookedTick = 0
    @State private var toast: String?
    @State private var showAddSheet = false
    @State private var pendingDeleteSlot: KaiXBookingSlotDTO?
    @State private var pendingCancelSlot: KaiXBookingSlotDTO?

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        Group {
            if loaded && (!slots.isEmpty || isOwner) {
                KXListingSection(title: titleText, icon: "calendar.badge.clock") {
                    VStack(alignment: .leading, spacing: 14) {
                        if slots.isEmpty {
                            Text(KXListingCopy.pickText(language,
                                                        "还没有可预约的时段，添加后买家/租客就能直接在线预约。",
                                                        "予約枠がまだありません。追加すると相手が直接予約できます。",
                                                        "No slots yet — add some so people can reserve online."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            dayStrip
                            slotGrid
                        }
                        if isOwner {
                            Button {
                                showAddSheet = true
                            } label: {
                                Label(KXListingCopy.pickText(language, "添加预约时段", "予約枠を追加", "Add a slot"),
                                      systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(KXColor.livingAccent)
                            }
                            .buttonStyle(KXPressableStyle())
                            if !slots.isEmpty {
                                Text(KXListingCopy.pickText(language, "长按时段可删除", "長押しで削除できます", "Long-press a slot to remove it"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if let toast {
                            Label(toast, systemImage: toast.contains("成功") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(toast.contains("成功") ? KXColor.livingAccent : KXColor.livingWarm)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        // After a successful booking, give the user a stable way to
                        // reach "我的预约" (the toast alone left them with no next step).
                        // Pushes onto the current stack via the shared route — no tab
                        // switch, no sheet-dismiss timing hazards.
                        if bookedTick > 0 {
                            Button {
                                router.open(.myReservations)
                            } label: {
                                Label(KXListingCopy.pickText(language, "查看我的预约", "予約を見る", "View my reservations"),
                                      systemImage: "calendar.badge.checkmark")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(KXColor.livingAccent)
                            }
                            .buttonStyle(KXPressableStyle())
                        }
                        Label(KXListingCopy.pickText(language,
                                                     "预约不收取任何费用，具体时间请到店/看房时与对方确认。",
                                                     "予約は無料です。詳細は現地で相手にご確認ください。",
                                                     "Booking is free — confirm the exact time with the host on arrival."),
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: listingId) { await reload() }
        .sensoryFeedback(.success, trigger: bookedTick)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedDayKey)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: bookedTick)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: slots.count)
        .sheet(isPresented: $showAddSheet) {
            AddBookingSlotSheet { startAt, capacity, note in
                Task { await addSlots([KaiXAPIClient.SlotInput(startAt: startAt, capacity: capacity, note: note)]) }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            KXListingCopy.pickText(language, "删除这个预约时段？", "この予約枠を削除しますか？", "Remove this slot?"),
            isPresented: Binding(get: { pendingDeleteSlot != nil }, set: { if !$0 { pendingDeleteSlot = nil } }),
            titleVisibility: .visible
        ) {
            Button(KXListingCopy.pickText(language, "删除", "削除", "Remove"), role: .destructive) {
                if let s = pendingDeleteSlot { Task { await deleteSlot(s) } }
                pendingDeleteSlot = nil
            }
            Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel"), role: .cancel) { pendingDeleteSlot = nil }
        } message: {
            Text(KXListingCopy.pickText(language, "已预约的用户会收到取消通知。", "予約済みのユーザーに取消通知が届きます。", "Anyone booked will be notified of the cancellation."))
        }
        .confirmationDialog(
            KXListingCopy.pickText(language, "取消你的预约？", "予約をキャンセルしますか？", "Cancel your reservation?"),
            isPresented: Binding(get: { pendingCancelSlot != nil }, set: { if !$0 { pendingCancelSlot = nil } }),
            titleVisibility: .visible
        ) {
            Button(KXListingCopy.pickText(language, "取消预约", "予約をキャンセル", "Cancel reservation"), role: .destructive) {
                if let s = pendingCancelSlot { Task { await cancelMyBooking(s) } }
                pendingCancelSlot = nil
            }
            Button(KXListingCopy.pickText(language, "返回", "戻る", "Keep"), role: .cancel) { pendingCancelSlot = nil }
        }
    }

    // Day pills (distinct days that have slots).
    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(dayKeys, id: \.self) { key in
                    let date = firstDate(forDay: key)
                    Button {
                        selectedDayKey = key
                    } label: {
                        VStack(spacing: 3) {
                            Text(weekdayText(date))
                                .font(.caption2.weight(.semibold))
                            Text(dayNumberText(date))
                                .font(.headline.weight(.bold))
                        }
                        .frame(width: 52, height: 60)
                        .foregroundStyle(key == selectedDayKey ? .white : KXColor.livingInk)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(key == selectedDayKey ? AnyShapeStyle(KXColor.livingAccent) : AnyShapeStyle(KXColor.livingAccentSoft.opacity(0.5)))
                        )
                    }
                    .buttonStyle(KXPressableStyle())
                }
            }
            .padding(.vertical, KXSpacing.xxs)
        }
    }

    // Time-slot chips for the selected day.
    private var slotGrid: some View {
        FlowLayout(spacing: 10) {
            ForEach(slotsForSelectedDay) { slot in
                slotChip(slot)
            }
        }
    }

    @ViewBuilder
    private func slotChip(_ slot: KaiXBookingSlotDTO) -> some View {
        let booked = slot.resolvedBookedByMe
        let full = slot.resolvedIsFull && !booked
        let busy = inFlightSlotId == slot.id
        Button {
            if isOwner { return }
            if booked { pendingCancelSlot = slot } else { Task { await book(slot) } }
        } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.mini).tint(KXColor.livingAccent)
                } else if booked {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(timeText(slot.startDate))
                    .font(.subheadline.weight(.bold))
                if booked {
                    Text(KXListingCopy.pickText(language, "已预约", "予約済み", "Booked")).font(.caption2.weight(.semibold))
                } else if full {
                    Text(KXListingCopy.pickText(language, "已约满", "満席", "Full")).font(.caption2.weight(.semibold))
                } else {
                    Text(KXListingCopy.pickText(language, "剩\(slot.resolvedAvailable)", "残\(slot.resolvedAvailable)", "\(slot.resolvedAvailable) left"))
                        .font(.caption2.weight(.semibold)).opacity(0.85)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(chipForeground(booked: booked, full: full))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(booked ? AnyShapeStyle(KXColor.livingAccent.opacity(0.14)) : AnyShapeStyle(KXColor.livingSurface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(booked ? KXColor.livingAccent : (full ? Color.secondary.opacity(0.25) : KXColor.livingAccent.opacity(0.45)),
                            lineWidth: 1.2)
            )
        }
        .buttonStyle(KXPressableStyle())
        .disabled(busy || (!isOwner && full && !booked))
        .onLongPressGesture(minimumDuration: 0.4) {
            if isOwner { pendingDeleteSlot = slot }
        }
    }

    private func chipForeground(booked: Bool, full: Bool) -> Color {
        if booked { return KXColor.livingAccent }
        if full { return .secondary }
        return KXColor.livingInk
    }

    // MARK: - Data

    private var dayKeys: [String] {
        var seen = Set<String>(); var ordered: [String] = []
        for s in slots {
            guard let d = s.startDate else { continue }
            let k = Self.dayKeyFormatter.string(from: d)
            if !seen.contains(k) { seen.insert(k); ordered.append(k) }
        }
        return ordered
    }

    private var slotsForSelectedDay: [KaiXBookingSlotDTO] {
        guard let key = selectedDayKey ?? dayKeys.first else { return [] }
        return slots.filter { s in
            guard let d = s.startDate else { return false }
            return Self.dayKeyFormatter.string(from: d) == key
        }
    }

    private func firstDate(forDay key: String) -> Date? {
        slots.first { s in
            guard let d = s.startDate else { return false }
            return Self.dayKeyFormatter.string(from: d) == key
        }?.startDate
    }

    private func reload() async {
        do {
            let resp = try await KaiXAPIClient.shared.listingSlots(listingId)
            await MainActor.run {
                slots = resp.items.sorted { ($0.startAt ?? "") < ($1.startAt ?? "") }
                isOwner = resp.isOwner ?? false
                if selectedDayKey == nil { selectedDayKey = dayKeys.first }
                loaded = true
            }
        } catch {
            await MainActor.run { loaded = true }   // hide section silently on failure
        }
    }

    private func addSlots(_ inputs: [KaiXAPIClient.SlotInput]) async {
        do {
            _ = try await KaiXAPIClient.shared.createListingSlots(listingId, slots: inputs)
            await reload()
            await MainActor.run {
                if selectedDayKey == nil { selectedDayKey = dayKeys.first }
                toast = KXListingCopy.pickText(language, "时段已添加", "枠を追加しました", "Slot added")
            }
        } catch {
            await MainActor.run { toast = KXListingCopy.pickText(language, "添加失败，请重试", "追加に失敗しました", "Failed to add") }
        }
    }

    private func deleteSlot(_ slot: KaiXBookingSlotDTO) async {
        do {
            try await KaiXAPIClient.shared.deleteListingSlot(listingId: listingId, slotId: slot.id)
            await reload()
            await MainActor.run {
                if let key = selectedDayKey, !dayKeys.contains(key) { selectedDayKey = dayKeys.first }
                toast = KXListingCopy.pickText(language, "时段已删除", "枠を削除しました", "Slot removed")
            }
        } catch {
            await MainActor.run { toast = KXListingCopy.pickText(language, "删除失败，请重试", "削除に失敗しました", "Failed to remove") }
        }
    }

    private func cancelMyBooking(_ slot: KaiXBookingSlotDTO) async {
        do {
            let mine = try await KaiXAPIClient.shared.myReservations()
            guard let booking = mine.first(where: { $0.slotId == slot.id && ($0.status ?? "confirmed") == "confirmed" }) else {
                await MainActor.run { toast = KXListingCopy.pickText(language, "未找到该预约", "予約が見つかりません", "Reservation not found") }
                return
            }
            try await KaiXAPIClient.shared.cancelReservation(booking.id)
            await reload()
            await MainActor.run { toast = KXListingCopy.pickText(language, "已取消预约", "予約をキャンセルしました", "Reservation cancelled") }
        } catch {
            await MainActor.run { toast = KXListingCopy.pickText(language, "取消失败，请重试", "キャンセルに失敗しました", "Failed to cancel") }
        }
    }

    private func book(_ slot: KaiXBookingSlotDTO) async {
        guard GuestSession.requireSignedIn(reason: KXListingCopy.pickText(language, "登录后可以在线预约时段。", "ログインするとオンラインで予約できます。", "Sign in to reserve a slot.")) else { return }
        guard inFlightSlotId == nil else { return }
        await MainActor.run { inFlightSlotId = slot.id; toast = nil }
        do {
            try await KaiXAPIClient.shared.bookSlot(listingId: listingId, slotId: slot.id)
            let resp = try? await KaiXAPIClient.shared.listingSlots(listingId)
            await MainActor.run {
                if let resp { slots = resp.items.sorted { ($0.startAt ?? "") < ($1.startAt ?? "") } }
                inFlightSlotId = nil
                bookedTick += 1
                toast = KXListingCopy.pickText(language, "预约成功，已加入「我的预约」", "予約が完了しました", "Reserved — see My reservations")
            }
        } catch {
            await MainActor.run {
                inFlightSlotId = nil
                toast = bookingErrorText(error)
            }
        }
    }

    private func bookingErrorText(_ error: Error) -> String {
        // Switch on the server's typed error code instead of fragile
        // localizedDescription substring matching — the latter broke as soon
        // as the backend returned a non-Chinese message, and silently fell
        // through to the generic copy.
        switch (error as? KaiXAPIError)?.error.code {
        case "AUTH_REQUIRED":
            return KXListingCopy.pickText(language, "请先登录后再预约", "ログインしてください", "Please sign in to book")
        case "slot_full":
            return KXListingCopy.pickText(language, "该时段已约满", "満席です", "This slot is full")
        case "already_booked":
            return KXListingCopy.pickText(language, "你已预约该时段", "予約済みです", "Already booked")
        case "slot_closed":
            return KXListingCopy.pickText(language, "该时段已关闭", "受付を終了しました", "This slot is closed")
        case "slot_not_found":
            return KXListingCopy.pickText(language, "该时段不存在", "この枠は存在しません", "This slot no longer exists")
        default:
            return KXListingCopy.pickText(language, "预约失败，请稍后再试", "予約に失敗しました", "Booking failed, try again")
        }
    }

    // MARK: - Formatting

    private var titleText: String {
        switch listingType {
        case "housing", "rental", "roommate":
            return KXListingCopy.pickText(language, "看房预约", "内見予約", "Book a viewing")
        case "local_service", "service", "discount", "event":
            return KXListingCopy.pickText(language, "预约到店", "来店予約", "Reserve a visit")
        default:
            return KXListingCopy.pickText(language, "预约时段", "予約枠", "Reservation")
        }
    }

    // Delegates to the shared DateFormatterUtils template cache — the old
    // per-call DateFormatter + setLocalizedDateFormatFromTemplate ran an ICU
    // pattern lookup for every slot chip on every render. The locale mapping
    // (zh_CN / ja_JP / en_US) is kept identical to the old switch.
    private var slotLocaleID: String {
        switch language {
        case .ja: return "ja_JP"
        case .en: return "en_US"
        default: return "zh_CN"
        }
    }

    private func weekdayText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return DateFormatterUtils.localizedTemplateString("EEE", localeID: slotLocaleID, date: date)
    }

    private func dayNumberText(_ date: Date?) -> String {
        guard let date else { return "" }
        return DateFormatterUtils.localizedTemplateString("Md", localeID: slotLocaleID, date: date)
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "" }
        return DateFormatterUtils.localizedTemplateString("Hm", localeID: slotLocaleID, date: date)
    }
}

/// Owner-side sheet to publish one bookable slot (date + time + capacity). No money.
struct AddBookingSlotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    /// (ISO8601 start, capacity, note)
    let onSave: (String, Int, String) -> Void

    @State private var date = Calendar.current.date(byAdding: .hour, value: 24, to: Date()) ?? Date()
    @State private var capacity = 1
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(KXListingCopy.pickText(language, "时间", "日時", "Time"),
                               selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Stepper(value: $capacity, in: 1...20) {
                        Text(KXListingCopy.pickText(language, "可约人数：\(capacity)", "受付人数：\(capacity)", "Capacity: \(capacity)"))
                    }
                    TextField(KXListingCopy.pickText(language, "备注（可选，如「每场30分钟」）", "メモ（任意）", "Note (optional)"),
                              text: $note)
                } footer: {
                    Text(KXListingCopy.pickText(language,
                                               "对方可在线预约该时段，不涉及任何费用。",
                                               "相手はこの枠をオンラインで予約できます（無料）。",
                                               "People can reserve this slot online — no payment involved."))
                }
            }
            .navigationTitle(KXListingCopy.pickText(language, "添加预约时段", "予約枠を追加", "Add a slot"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(KXListingCopy.pickText(language, "添加", "追加", "Add")) {
                        let f = ISO8601DateFormatter()
                        f.formatOptions = [.withInternetDateTime]
                        onSave(f.string(from: date), capacity, note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CityListingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState
    let listingId: String
    let currentUser: UserEntity
    /// Matches the source card's namespace for the zoom-in transition (router
    /// path only; nil → default push).
    var zoomNamespace: Namespace.ID? = nil

    @State private var listing: KaiXCityListingDTO?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var isBusy = false
    @State private var intakeOpen = false
    /// Local heart state layered over the immutable DTO so a favorite toggles
    /// instantly (optimistic, rolled back on failure) instead of waiting for a
    /// full-page reload. Cleared whenever a fresh listing loads.
    @State private var favoritedOverride: Bool?
    /// Report flow: pick a reason before submitting (also blocks fat-finger reports).
    @State private var reportConfirmOpen = false
    @State private var inquiryReceipt: ListingInquiryReceipt?
    @State private var similarItems: [KaiXCityListingDTO] = []
    @State private var sellerOtherItems: [KaiXCityListingDTO] = []
    /// 预约联系人卡里复制 LINE / 微信 ID 后的短暂提示。
    @State private var contactCopyConfirmation: String?
    /// 相册:当前页 + 全屏查看器(可缩放/保存)。
    @State private var galleryIndex = 0
    @State private var photoViewerPresented = false
    @State private var photoViewerStart = 0

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Group {
                if isLoading {
                    LoadingView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load() } }
                } else if let listing {
                    detailContent(listing)
                } else {
                    EmptyStateView(title: "信息不存在", subtitle: "它可能已下架或正在审核。", systemImage: "tray")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let listing, !isLoading, errorMessage == nil {
                detailStickyBar(listing)
            }
        }
        .kxPageBackground()
        .kxListingZoomDestination("listing-\(listingId)", zoomNamespace)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: listingId) { await load() }
        .confirmationDialog(
            KXListingCopy.pickText(language, "举报这条信息？", "この投稿を通報しますか？", "Report this listing?"),
            isPresented: $reportConfirmOpen,
            titleVisibility: .visible
        ) {
            Button(KXListingCopy.pickText(language, "虚假或诈骗信息", "虚偽・詐欺の疑い", "Fake or scam"), role: .destructive) {
                Task { await report(reason: "suspicious") }
            }
            Button(KXListingCopy.pickText(language, "广告或骚扰", "広告・迷惑行為", "Spam or harassment"), role: .destructive) {
                Task { await report(reason: "spam") }
            }
            Button(KXListingCopy.pickText(language, "不当内容", "不適切な内容", "Inappropriate content"), role: .destructive) {
                Task { await report(reason: "inappropriate") }
            }
            Button(KXListingCopy.pickText(language, "其他问题", "その他の問題", "Other issue"), role: .destructive) {
                Task { await report(reason: "other") }
            }
            Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(KXListingCopy.pickText(language, "选择举报理由，Machi 会尽快审核。", "通報理由を選んでください。Machi が確認します。", "Choose a reason — Machi will review it."))
        }
        .sheet(isPresented: $intakeOpen) {
            Group {
                if let listing {
                    ListingIntakeSheet(listingTitle: KXListingCopy.displayTitle(listing), listingType: listing.type, listingCategory: listing.category, submitting: isBusy) { message, details in
                        Task { await submitInquiry(message: message, details: details) }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $inquiryReceipt) { receipt in
            ListingInquirySuccessSheet(
                receipt: receipt,
                onOpenRecords: {
                    inquiryReceipt = nil
                    // Two things were broken here:
                    // 1. Switch the *visible* tab via chrome.select (which keeps
                    //    router.activeTab in sync). router.setActiveTab alone left the
                    //    visible tab on Search while activeTab moved to Profile, so the
                    //    button looked dead AND later router.open calls went to the
                    //    hidden Profile stack (Discover entries stopped responding).
                    // 2. Defer the tab switch + push until AFTER the sheet finishes
                    //    dismissing. Doing it in the same runloop tick as the dismiss
                    //    makes SwiftUI drop the navigation — the actual reason the
                    //    buttons did nothing.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        chrome.select(.profile)
                        router.popToRoot(.profile)
                        router.open(.myInquiries, in: .profile)
                    }
                },
                onOpenConversation: {
                    guard !receipt.conversationId.isEmpty else { return }
                    inquiryReceipt = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        chrome.select(.messages)
                        router.open(.conversation(conversationId: receipt.conversationId), in: .messages)
                    }
                },
                onClose: {
                    inquiryReceipt = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Airbnb-style sticky bottom bar: price on the left, primary CTA on the
    /// right, always reachable. Translucent glass so content scrolls under it.
    private func detailStickyBar(_ listing: KaiXCityListingDTO) -> some View {
        let ownListing = isOwnListing(listing)
        let spec = ListingIntakeSpec.forType(listing.type, category: listing.category)
        let isWork = listing.type == "job" || listing.type == "hiring"
        let ratingCount = listing.rating_count ?? listing.ratingCount ?? 0
        let ratingAvg = listing.rating_avg ?? listing.ratingAvg ?? 0
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(KXListingCopy.priceLabel(listing, language))
                    .font(.title3.weight(.black))
                    .foregroundStyle(isWork ? KXColor.livingAccent : KXColor.livingWarm)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if ratingCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").kxScaledFont(10, weight: .black).foregroundStyle(.orange)
                        Text(String(format: "%.1f", ratingAvg)).font(.caption2.weight(.black)).foregroundStyle(KXColor.livingInk)
                        Text("(\(ratingCount))").font(.caption2.weight(.semibold)).foregroundStyle(KXColor.livingMuted)
                    }
                } else {
                    Text(KXListingCopy.title(for: listing.type, language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KXColor.livingMuted)
                }
            }
            Spacer(minLength: 8)
            Button {
                if ownListing {
                    router.open(.editCityListing(listingId: listing.id))
                } else {
                    guard GuestSession.requireSignedIn(currentUser, reason: intakeLoginReason) else { return }
                    intakeOpen = true
                }
            } label: {
                Text(ownListing ? KXListingCopy.pickText(language, "编辑发布", "投稿を編集", "Edit listing") : ListingIntakeLocalizer.text(spec.title, language))
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 50)
                    .background(KXColor.livingAccent, in: Capsule())
                    .shadow(color: KXColor.livingAccent.opacity(0.32), radius: 10, y: 4)
            }
            .buttonStyle(KXPressableStyle(scale: 0.96))
            .disabled(isBusy)
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, KXSpacing.sm)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(KXColor.livingSurface.opacity(0.5)))
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(KXColor.livingInk.opacity(0.08)).frame(height: 0.5)
        }
    }

    /// Public web URL for the system share sheet — resolves back into the app
    /// via Universal Links (`/listings/<id>` → listing detail).
    private var listingShareURL: URL {
        URL(string: "https://machicity.com/listings/\(listingId)") ?? URL(string: "https://machicity.com")!
    }

    /// Share-sheet title: the listing's display title, with a branded fallback.
    private var listingShareTitle: String {
        guard let listing else { return "Machi" }
        let title = KXListingCopy.displayTitle(listing).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Machi" : title
    }

    private var detailHeader: some View {
        HStack(spacing: KXSpacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KXListingCopy.pickText(language, "返回", "戻る", "Back"))
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(KXListingCopy.title(for: listing?.type ?? "secondhand", language))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(KXColor.livingInk)
                Text(KXListingCopy.pickText(language, "详情与联系", "詳細・連絡", "Details & contact"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KXColor.livingMuted)
            }
            Spacer()
            ShareLink(
                item: listingShareURL,
                subject: Text(listingShareTitle),
                preview: SharePreview(listingShareTitle)
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KXListingCopy.pickText(language, "分享", "共有", "Share"))
            Button { Task { await favorite() } } label: {
                Image(systemName: isFavoritedNow ? "heart.fill" : "heart")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isFavoritedNow ? KXColor.heat : .primary)
                    .symbolEffect(.bounce, value: isFavoritedNow)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("like", language))
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.md)
        .background(KXColor.livingBackground.opacity(0.94))
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    /// 商家与服务详情：团购套餐(展示「暂不支持线上购买」) + 菜单 + 预约·到店。
    @ViewBuilder
    private func merchantDetailSections(_ listing: KaiXCityListingDTO) -> some View {
        if listing.type == "local_service", KXListingCopy.serviceVertical(for: listing) == .foodRestaurant {
            let packages = listing.groupPackages
            let dishes = listing.menuDishes
            let openHours = KXListingCopy.attr(listing, "open_hours") ?? ""
            let reservationNote = KXListingCopy.attr(listing, "reservation_note") ?? ""
            let storePhone = KXListingCopy.attr(listing, "store_phone") ?? ""
            let reservationRequired = listing.attributes?["reservation_required"]?.boolValue ?? false
            let hasReservation = reservationRequired || !openHours.isEmpty || !reservationNote.isEmpty || !storePhone.isEmpty

            if !packages.isEmpty {
                KXListingSection(title: KXListingCopy.pickText(language, "团购套餐", "セット・クーポン", "Packages"), icon: "ticket") {
                    VStack(spacing: 10) {
                        HStack {
                            Spacer()
                            Text(KXListingCopy.pickText(language, "暂不支持线上购买", "オンライン購入は未対応", "Online purchase unavailable"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, KXSpacing.sm).padding(.vertical, KXSpacing.xs)
                                .background(KXColor.livingSoft, in: Capsule())
                        }
                        ForEach(packages) { pkg in
                            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(pkg.title ?? "").font(.subheadline.weight(.black)).foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    if let price = pkg.price, !price.isEmpty {
                                        Text(price).font(.subheadline.weight(.black)).foregroundStyle(KXColor.livingWarm)
                                    }
                                    if let orig = pkg.original_price, !orig.isEmpty {
                                        Text(orig).font(.caption.weight(.semibold)).foregroundStyle(.secondary).strikethrough()
                                    }
                                }
                                if let inc = pkg.includes, !inc.isEmpty {
                                    Text(inc).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                if let note = pkg.note, !note.isEmpty {
                                    Text(note).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(KXSpacing.md)
                            .background(KXColor.livingSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }

            if !dishes.isEmpty {
                KXListingSection(title: KXListingCopy.pickText(language, "菜单", "メニュー", "Menu"), icon: "fork.knife") {
                    VStack(spacing: 0) {
                        ForEach(Array(dishes.enumerated()), id: \.offset) { idx, dish in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                                    Text(dish.name ?? "").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                                    if let d = dish.desc, !d.isEmpty {
                                        Text(d).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                if let price = dish.price, !price.isEmpty {
                                    Text(price).font(.subheadline.weight(.black)).foregroundStyle(KXColor.livingWarm)
                                }
                            }
                            .padding(.vertical, 9)
                            if idx < dishes.count - 1 { Divider().opacity(0.5) }
                        }
                    }
                }
            }

            if hasReservation {
                KXListingSection(title: KXListingCopy.pickText(language, "预约 · 到店", "予約・来店", "Booking & visit"), icon: "calendar.badge.clock") {
                    VStack(alignment: .leading, spacing: 6) {
                        if !openHours.isEmpty {
                            Label("\(KXListingCopy.pickText(language, "营业时间", "営業時間", "Hours")) · \(openHours)", systemImage: "clock")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if reservationRequired {
                            Label(KXListingCopy.pickText(language, "本店采用预约制，建议先预约再到店。", "予約制です。来店前の予約をおすすめします。", "Reservation is recommended before visiting."), systemImage: "checkmark.seal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !reservationNote.isEmpty { Text(reservationNote).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        if !storePhone.isEmpty {
                            Label("\(KXListingCopy.pickText(language, "到店电话", "店舗電話", "Phone")) · \(storePhone)", systemImage: "phone")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func detailContent(_ listing: KaiXCityListingDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                imageStrip(listing)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            if listing.isMachiRecommended {
                                HStack(spacing: KXSpacing.xs) {
                                    Image(systemName: "sparkles")
                                    Text(KXListingCopy.pickText(language, "Machi推荐", "Machiおすすめ", "Machi Pick"))
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(KXColor.rankGold, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 0.7))
                            }
                            Text(KXListingCopy.priceLabel(listing, language))
                                .font(.title2.weight(.black))
                                .foregroundStyle(listing.type == "job" || listing.type == "hiring" ? KXColor.livingAccent : KXColor.livingWarm)
                            Text(KXListingCopy.displayTitle(listing))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(KXColor.livingInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        KXListingBadge(title: KXListingCopy.statusLabel(listing.status, type: listing.type, language), tint: KXListingCopy.statusColor(listing.status))
                    }
                    FlowLayout(spacing: KXSpacing.sm) {
                        ForEach(KXListingCopy.badges(for: listing, language), id: \.self) { badge in
                            KXListingBadge(title: badge, tint: KXColor.livingAccent)
                        }
                    }
                }
                .padding(KXSpacing.lg)
                .kxLivingSurface(radius: KXRadius.hero, elevated: true)

                KXListingAttributeSection(listing: listing)

                if let description = listing.description, !description.isEmpty {
                    KXListingSection(title: KXListingCopy.pickText(language, "描述", "説明", "Description"), icon: "text.alignleft") {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                merchantDetailSections(listing)

                if let contact = listing.reservationContact {
                    reservationContactCard(contact)
                }

                ListingBookingSection(listingId: listing.id, listingType: listing.type)

                KXListingSection(title: KXListingCopy.pickText(language, "发布者", "投稿者", "Poster"), icon: "person.crop.circle") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: KXSpacing.md) {
                            Circle()
                                .fill(KXColor.livingAccentSoft)
                                .frame(width: 44, height: 44)
                                .overlay(Text((listing.seller?.display_name ?? "M").prefix(1)).font(.headline.weight(.bold)).foregroundStyle(KXColor.livingAccent))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(listing.seller?.display_name ?? KXListingCopy.pickText(language, "Machi 用户", "Machi ユーザー", "Machi user"))
                                    .font(.subheadline.weight(.bold))
                                Text(KXListingCopy.verificationLabel(listing.verification_status, language))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        trustChipRow(listing)
                        if sellerIsNew(listing) && !sellerVerified(listing) {
                            Label(KXListingCopy.pickText(language, "新账号，交易前请多核实身份、当面验货", "新規アカウントです。取引前に本人確認と現物確認をおすすめします", "New account — verify identity and inspect in person before trading"), systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }

                ListingReviewsSectionView(listing: listing, currentUser: currentUser)

                if !sellerOtherItems.isEmpty {
                    listingRail(title: KXListingCopy.pickText(language, "TA 的其他发布", "このユーザーの他の投稿", "More from this poster"), icon: "person.crop.rectangle.stack", items: sellerOtherItems)
                }
                if !similarItems.isEmpty {
                    listingRail(title: KXListingCopy.pickText(language, "相似推荐", "関連おすすめ", "Similar listings"), icon: "sparkles.rectangle.stack", items: similarItems)
                }

                KXListingSection(
                    title: KXListingCopy.isHighRisk(listing.type)
                        ? KXListingCopy.pickText(language, "高风险类目 · 谨慎交易", "高リスクカテゴリ・取引注意", "High-risk category · trade carefully")
                        : KXListingCopy.pickText(language, "安全提醒", "安全の注意", "Safety tips"),
                    icon: KXListingCopy.isHighRisk(listing.type) ? "exclamationmark.shield.fill" : "shield.checkered"
                ) {
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        if KXListingCopy.isHighRisk(listing.type) {
                            Text(KXListingCopy.pickText(language,
                                "Machi 只是信息平台，不代收任何押金 / 订金 / 货款，任何要求提前转账的都要高度警惕。",
                                "Machi は情報プラットフォームであり、敷金・申込金・代金を一切預かりません。事前送金を求められたら十分にご注意ください。",
                                "Machi is only an info platform and never holds deposits or payments. Be very cautious of any upfront-transfer request."))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(KXListingCopy.safetyTips(for: listing.type, language), id: \.self) { tip in
                            Label(tip, systemImage: "checkmark.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let msg = actionMessage {
                    Text(msg)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KXColor.livingAccent)
                        .padding(.horizontal, KXSpacing.xxs)
                        .task(id: msg) {
                            // Auto-dismiss the transient status/error line so it
                            // doesn't linger after the action it described is done.
                            try? await Task.sleep(for: .seconds(4))
                            if actionMessage == msg { actionMessage = nil }
                        }
                }

                contactPanel(listing)
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    /// 预约联系人卡（星域东京专属房源）：姓名 + 职位，按可用渠道列出
    /// 电话 / LINE / 微信 / WhatsApp / 邮箱 / 语言；电话邮箱可点拨打/发信，
    /// LINE 与微信 ID 点击复制并给出短暂提示。
    @ViewBuilder
    private func reservationContactCard(_ contact: KaiXReservationContactDTO) -> some View {
        let name = (contact.name ?? contact.nameJa)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        KXListingSection(title: KXListingCopy.pickText(language, "预约联系人", "予約担当", "Reservation contact"), icon: "person.crop.circle.badge.checkmark") {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(spacing: KXSpacing.md) {
                    contactAvatar(contact, name: name)
                    VStack(alignment: .leading, spacing: 3) {
                        if !name.isEmpty {
                            Text(name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(KXColor.livingInk)
                        }
                        if let title = contact.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    if let phone = cleanContactValue(contact.phone) {
                        Link(destination: URL(string: "tel:\(phone.filter { !$0.isWhitespace })") ?? URL(string: "tel:")!) {
                            contactRowLabel(icon: "phone.fill", value: phone, tappable: true)
                        }
                    }
                    if let line = cleanContactValue(contact.lineId) {
                        Button {
                            copyContactValue(line, label: "LINE")
                        } label: {
                            contactRowLabel(icon: "message.fill", value: "LINE · \(line)", tappable: true)
                        }
                        .buttonStyle(.plain)
                    }
                    if let wechat = cleanContactValue(contact.wechatId) {
                        Button {
                            copyContactValue(wechat, label: KXListingCopy.pickText(language, "微信", "WeChat", "WeChat"))
                        } label: {
                            contactRowLabel(icon: "bubble.left.and.bubble.right.fill", value: "\(KXListingCopy.pickText(language, "微信", "WeChat", "WeChat")) · \(wechat)", tappable: true)
                        }
                        .buttonStyle(.plain)
                    }
                    if let whatsapp = cleanContactValue(contact.whatsapp) {
                        let digits = whatsapp.filter { $0.isNumber }
                        let url = URL(string: "https://wa.me/\(digits)") ?? URL(string: "https://wa.me")!
                        Link(destination: url) {
                            contactRowLabel(icon: "phone.bubble.fill", value: "WhatsApp · \(whatsapp)", tappable: true)
                        }
                    }
                    if let email = cleanContactValue(contact.email) {
                        Link(destination: URL(string: "mailto:\(email)") ?? URL(string: "mailto:")!) {
                            contactRowLabel(icon: "envelope.fill", value: email, tappable: true)
                        }
                    }
                    if let languages = cleanContactValue(contact.languages) {
                        contactRowLabel(icon: "globe", value: languages, tappable: false)
                    }
                }

                if let confirmation = contactCopyConfirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KXColor.livingAccent)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func contactAvatar(_ contact: KaiXReservationContactDTO, name: String) -> some View {
        if let photo = cleanContactValue(contact.photoUrl), let url = URL(string: photo) {
            // Cached + downsampled via the app's image pipeline
            // (CachedMediaImageView → ImageCacheService) instead of a bare
            // AsyncImage, which re-downloaded the full-size photo on every
            // appearance. The soft accent circle underneath mirrors the old
            // AsyncImage placeholder while loading / on failure.
            ZStack {
                Circle().fill(KXColor.livingAccentSoft)
                CachedMediaImageView(url: url, targetPixelSize: 44 * 3, failureMode: .transparent)
                    .clipShape(Circle())
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(KXColor.livingAccentSoft)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(name.isEmpty ? "M" : String(name.prefix(1)))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                )
        }
    }

    private func contactRowLabel(icon: String, value: String, tappable: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KXColor.livingAccent)
                .frame(width: 22)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(tappable ? KXColor.livingAccent : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func cleanContactValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func copyContactValue(_ value: String, label: String) {
        UIPasteboard.general.string = value
        withAnimation { contactCopyConfirmation = String(format: KXListingCopy.pickText(language, "已复制 %@", "%@をコピーしました", "Copied %@"), label) }
        let confirmed = contactCopyConfirmation
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if contactCopyConfirmation == confirmed {
                withAnimation { contactCopyConfirmation = nil }
            }
        }
    }

    private func imageStrip(_ listing: KaiXCityListingDTO) -> some View {
        // Drop server-generated placeholder media so the gallery shows a clean
        // native placeholder instead of the "Generated default cover" card.
        let realMedia = (listing.media ?? []).filter { !KaiXCityListingDTO.isGeneratedCover($0.url) }
        let mediaItems: [KaiXListingMediaDTO]
        if !realMedia.isEmpty {
            mediaItems = realMedia
        } else if let cover = listing.primaryCoverMedia, !KaiXCityListingDTO.isGeneratedCover(cover.url) {
            mediaItems = [cover]
        } else {
            mediaItems = []
        }
        // 全屏查看器只放图片(视频在原地播放)。
        let imageMedia = mediaItems.filter { $0.normalizedType != "video" }
        return Group {
            if mediaItems.isEmpty {
                ListingMediaPlaceholder(type: listing.type)
            } else {
                TabView(selection: $galleryIndex) {
                    ForEach(Array(mediaItems.enumerated()), id: \.offset) { index, media in
                        ListingMediaPage(media: media, index: index, total: mediaItems.count, showsCounter: false)
                            .tag(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard media.normalizedType != "video" else { return }
                                photoViewerStart = imageMedia.firstIndex(where: { $0.id == media.id }) ?? 0
                                photoViewerPresented = true
                            }
                    }
                }
                // 自带 .page 圆点会被圆角裁掉「往下隐藏」——改用不会被裁的角标计数器。
                .tabViewStyle(.page(indexDisplayMode: .never))
                .overlay(alignment: .bottomTrailing) {
                    if mediaItems.count > 1 {
                        let shown = min(max(galleryIndex, 0), mediaItems.count - 1) + 1
                        Text("\(shown)/\(mediaItems.count)")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, KXSpacing.sm)
                            .frame(height: 24)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(10)
                    }
                }
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.07), radius: 16, y: 7)
        .fullScreenCover(isPresented: $photoViewerPresented) {
            ListingPhotoViewer(media: imageMedia, startIndex: photoViewerStart)
        }
    }

    private func contactPanel(_ listing: KaiXCityListingDTO) -> some View {
        let spec = ListingIntakeSpec.forType(listing.type, category: listing.category)
        let ownListing = isOwnListing(listing)
        return KXListingSection(title: KXListingCopy.pickText(language, "申请/预约/咨询", "応募・予約・問い合わせ", "Apply, book or inquire"), icon: "tray.full") {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: ownListing ? "person.crop.circle.badge.checkmark" : "doc.badge.clock")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ownListing ? .secondary : KXColor.livingAccent)
                        .frame(width: 38, height: 38)
                        .background(ownListing ? Color.secondary.opacity(0.12) : KXColor.livingAccentSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ownListing
                             ? KXListingCopy.pickText(language, "这是你的发布", "これはあなたの投稿です", "This is your listing")
                             : KXListingCopy.pickText(language, "提交申请、预约或咨询", "応募・予約・問い合わせを送信", "Submit an application, booking or inquiry"))
                            .font(.subheadline.weight(.bold))
                        Text(ownListing
                             ? KXListingCopy.pickText(language, "自己的发布不能发起咨询，可以在我的发布中管理状态。", "自分の投稿には問い合わせできません。投稿管理から状態を変更できます。", "You cannot inquire about your own listing. Manage it from My listings.")
                             : KXListingCopy.pickText(language, "提交后会生成正式记录，私信只用于后续补充沟通。", "送信後は正式な記録が作成され、メッセージは補足連絡用です。", "Submitting creates an official record; messages are only for follow-up."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if ownListing {
                    // 自己的发布：联系按钮换成直达编辑，管理动作不再是死路。
                    Button {
                        router.open(.editCityListing(listingId: listing.id))
                    } label: {
                        Label(KXListingCopy.pickText(language, "编辑这条发布", "この投稿を編集", "Edit this listing"), systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(KXColor.livingAccent, in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                } else {
                    Button {
                        guard GuestSession.requireSignedIn(currentUser, reason: intakeLoginReason) else { return }
                        intakeOpen = true
                    } label: {
                        Label(isBusy ? KXListingCopy.pickText(language, "处理中", "処理中", "Processing") : ListingIntakeLocalizer.text(spec.title, language), systemImage: "doc.badge.plus")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(KXColor.livingAccent, in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }

                if listing.type == "secondhand", !ownListing {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: KXSpacing.sm), GridItem(.flexible(), spacing: KXSpacing.sm)], spacing: KXSpacing.sm) {
                        ForEach(quickInquiries(for: listing)) { item in
                            Button {
                                Task { await submitInquiry(message: item.message, details: item.details) }
                            } label: {
                                Text(item.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(KXColor.livingAccent)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(KXColor.livingAccentSoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy)
                        }
                    }
                }

                HStack(spacing: KXSpacing.sm) {
                    Button {
                        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以举报异常信息。", "ログインすると問題を報告できます。", "Sign in to report a listing.")) else { return }
                        reportConfirmOpen = true
                    } label: {
                        Label(KXListingCopy.pickText(language, "举报异常", "問題を報告", "Report issue"), systemImage: "flag")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    Text(KXListingCopy.pickText(language, "不要提前转账，建议公共场所交易。", "前払いは避け、公共の場所での取引をおすすめします。", "Avoid paying in advance; meet in public when trading."))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func isOwnListing(_ listing: KaiXCityListingDTO) -> Bool {
        let sellerId = listing.seller_user_id ?? listing.sellerUserId ?? ""
        return listing.can_manage == true || listing.canManage == true || sellerId == currentUser.id
    }

    private func sellerVerified(_ listing: KaiXCityListingDTO) -> Bool {
        let s = listing.seller
        return s?.is_verified == true || s?.is_verified_member == true || s?.merchant_verified == true || listing.verification_status == "verified"
    }

    private func sellerJoinDate(_ listing: KaiXCityListingDTO) -> Date? {
        let iso = listing.seller?.joined_at ?? listing.seller?.created_at
        guard let iso, !iso.isEmpty else { return nil }
        // Cached shared ISO parsers (same fractional→plain fallback order)
        // instead of allocating a fresh ISO8601DateFormatter per render —
        // this runs for the trust-chip row every time the detail redraws.
        if let d = KXDateParsing.isoFractional.date(from: iso) { return d }
        return KXDateParsing.iso.date(from: iso)
    }

    private func sellerIsNew(_ listing: KaiXCityListingDTO) -> Bool {
        guard let d = sellerJoinDate(listing) else { return false }
        return Date().timeIntervalSince(d) < 14 * 24 * 60 * 60
    }

    @ViewBuilder
    private func trustChipRow(_ listing: KaiXCityListingDTO) -> some View {
        let verified = sellerVerified(listing)
        let heat = Int(listing.seller?.total_heat ?? 0)
        HStack(spacing: KXSpacing.sm) {
            trustChip(
                icon: verified ? "checkmark.seal.fill" : "seal",
                text: verified
                    ? KXListingCopy.pickText(language, "已实名认证", "本人確認済み", "Verified")
                    : KXListingCopy.pickText(language, "未认证", "未認証", "Unverified"),
                tint: verified ? .green : .secondary
            )
            if let d = sellerJoinDate(listing) {
                trustChip(icon: "calendar", text: DateFormatterUtils.localizedTemplateString("yMMM", localeID: DateFormatterUtils.localeID(for: language), date: d), tint: .secondary)
            }
            if heat > 0 {
                trustChip(icon: "flame.fill", text: KXListingCopy.pickText(language, "贡献值 \(heat)", "貢献度 \(heat)", "Contribution \(heat)"), tint: .orange)
            }
            Spacer(minLength: 0)
        }
    }

    private func trustChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, KXSpacing.sm)
        .padding(.vertical, KXSpacing.xs)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func quickInquiries(for listing: KaiXCityListingDTO) -> [ListingQuickInquiry] {
        let title = KXListingCopy.displayTitle(listing)
        let location = listing.location_text ?? listing.locationText ?? ""
        return [
            ListingQuickInquiry(
                id: "available",
                title: KXListingCopy.pickText(language, "还在吗？", "まだありますか？", "Still available?"),
                message: KXListingCopy.pickText(
                    language,
                    "你好，我想确认「\(title)」还可以交易吗？",
                    "こんにちは。「\(title)」はまだ取引できますか？",
                    "Hi, is \"\(title)\" still available?"
                ),
                details: [["label": KXListingCopy.pickText(language, "咨询内容", "内容", "Question"), "value": KXListingCopy.pickText(language, "确认是否仍可交易", "まだ取引可能か確認", "Check availability")]]
            ),
            ListingQuickInquiry(
                id: "meetup",
                title: KXListingCopy.pickText(language, "约自取", "受け取り相談", "Meet up"),
                message: KXListingCopy.pickText(
                    language,
                    "你好，我想预约自取「\(title)」，方便的话请告诉我可交易时间。",
                    "こんにちは。「\(title)」の受け取りを相談したいです。可能な日時を教えてください。",
                    "Hi, I would like to arrange pickup for \"\(title)\". Please let me know a good time."
                ),
                details: [
                    ["label": KXListingCopy.pickText(language, "希望交易方式", "希望取引方法", "Preferred handoff"), "value": KXListingCopy.pickText(language, "自取 / 面交", "受け取り / 対面", "Pickup / meet up")],
                    ["label": KXListingCopy.pickText(language, "希望地点", "希望場所", "Preferred location"), "value": location]
                ]
            ),
            ListingQuickInquiry(
                id: "condition",
                title: KXListingCopy.pickText(language, "问瑕疵", "状態確認", "Condition"),
                message: KXListingCopy.pickText(
                    language,
                    "你好，我想了解「\(title)」的使用痕迹、配件和是否有瑕疵。",
                    "こんにちは。「\(title)」の使用感、付属品、傷などを確認したいです。",
                    "Hi, I would like to know the condition, accessories, and any defects for \"\(title)\"."
                ),
                details: [["label": KXListingCopy.pickText(language, "咨询内容", "内容", "Question"), "value": KXListingCopy.pickText(language, "确认状态、配件和瑕疵", "状態・付属品・傷の確認", "Condition, accessories, and defects")]]
            ),
            ListingQuickInquiry(
                id: "price",
                title: KXListingCopy.pickText(language, "可议价吗？", "価格相談", "Negotiate"),
                message: KXListingCopy.pickText(
                    language,
                    "你好，我对「\(title)」感兴趣，想问一下价格是否可以商量。",
                    "こんにちは。「\(title)」に興味があります。価格相談は可能ですか？",
                    "Hi, I am interested in \"\(title)\". Is the price negotiable?"
                ),
                details: [["label": KXListingCopy.pickText(language, "咨询内容", "内容", "Question"), "value": KXListingCopy.pickText(language, "价格是否可商量", "価格相談の可否", "Whether the price is negotiable")]]
            ),
        ]
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await KaiXAPIClient.shared.cityListing(listingId)
            listing = loaded
            // Fresh server truth supersedes any optimistic heart override.
            favoritedOverride = nil
            isLoading = false
            await loadRecommendations(for: loaded)
        } catch {
            errorMessage = error.kaixUserMessage
            isLoading = false
        }
    }

    /// 相似推荐 + TA 的其他发布。推荐栏失败不影响详情主体。
    private func loadRecommendations(for loaded: KaiXCityListingDTO) async {
        let sellerId = loaded.seller_user_id ?? loaded.sellerUserId ?? ""
        let viewerId = currentUser.id
        async let similarTask = try? KaiXAPIClient.shared.similarListings(loaded.id)
        async let sellerTask: [KaiXCityListingDTO]? = sellerId.isEmpty || sellerId == viewerId
            ? nil
            : try? KaiXAPIClient.shared.listingsPage(
                type: loaded.type,
                sellerId: sellerId,
                excludeListingId: loaded.id,
                limit: 8
            ).items
        similarItems = (await similarTask) ?? []
        sellerOtherItems = (await sellerTask) ?? []
    }

    private func listingRail(title: String, icon: String, items: [KaiXCityListingDTO]) -> some View {
        KXListingSection(title: title, icon: icon) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: KXSpacing.md) {
                    ForEach(items) { item in
                        KXSecondhandListingCard(listing: item, width: 150) {
                            router.open(.cityListingDetail(listingId: item.id))
                        }
                    }
                }
            }
        }
    }

    /// True when the heart should render filled — the optimistic override wins
    /// over the (immutable) DTO's server-provided flag.
    private var isFavoritedNow: Bool {
        favoritedOverride ?? (listing?.favorited ?? listing?.isFavorited ?? false)
    }

    /// Shared login-prompt copy for the inquiry / booking / application entry points.
    private var intakeLoginReason: String {
        KXListingCopy.pickText(language, "登录后可以提交申请、预约或咨询。", "ログインすると応募・予約・問い合わせができます。", "Sign in to apply, book or inquire.")
    }

    private func favorite() async {
        guard let listing else { return }
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以收藏喜欢的信息。", "ログインするとお気に入りに保存できます。", "Sign in to save listings you like.")) else { return }
        let current = isFavoritedNow
        let next = !current
        // Route the write through FavoritesStore (like the listing cards do) so
        // the local wishlist cache stays consistent with the heart shown on the
        // cards. Optimistic flip (heart + local cache) + rollback on failure —
        // no full-page reload, the heart responds instantly.
        let snapshot = FavoritesStore.snapshot(from: listing)
        favoritedOverride = next
        FavoritesStore.shared.set(snapshot, on: next)
        isBusy = true
        defer { isBusy = false }
        do {
            try await KaiXAPIClient.shared.favoriteListing(listing.id, on: next)
        } catch {
            favoritedOverride = current
            FavoritesStore.shared.set(snapshot, on: current)
            actionMessage = error.kaixUserMessage
        }
    }

    private func submitInquiry(message: String, details: [[String: String]]) async {
        guard let listing else { return }
        // Backstop for the sheet-less quick-inquiry buttons; the sheet entry
        // points are gated before the sheet ever opens.
        guard GuestSession.requireSignedIn(currentUser, reason: intakeLoginReason) else { return }
        guard !isOwnListing(listing) else {
            actionMessage = KXListingCopy.pickText(language, "不能咨询自己发布的信息。", "自分の投稿には問い合わせできません。", "You cannot inquire about your own listing.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let spec = ListingIntakeSpec.forType(listing.type, category: listing.category)
            let actionWord = ListingIntakeLocalizer.text(spec.actionWord, language)
            let fallback = KXListingCopy.pickText(
                language,
                "我想\(actionWord)：\(KXListingCopy.displayTitle(listing))",
                "\(actionWord)：\(KXListingCopy.displayTitle(listing))",
                "\(actionWord): \(KXListingCopy.displayTitle(listing))"
            )
            let locale = language == .zh ? "zh-Hans" : language.rawValue
            let receiptDTO = try await KaiXAPIClient.shared.contactListing(
                listing.id,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : message,
                details: details,
                locale: locale
            )
            intakeOpen = false
            actionMessage = receiptDTO.resolvedSuccessTitle
            // Remember this conversation so a later reply reads as a
            // "consultation got a reply" delight moment for the rating prompt.
            ReviewPromptService.shared.rememberInquiryConversation(receiptDTO.resolvedConversationId)
            try? await Task.sleep(for: .milliseconds(220))
            inquiryReceipt = ListingInquiryReceipt(
                listingTitle: KXListingCopy.displayTitle(listing),
                listingType: listing.type,
                receipt: receiptDTO
            )
        } catch {
            actionMessage = error.kaixUserMessage
        }
    }

    private func report(reason: String) async {
        guard let listing else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await KaiXAPIClient.shared.reportListing(listing.id, reason: reason, note: "App 用户举报")
            actionMessage = KXListingCopy.pickText(language, "举报已提交，Machi 会进行审核。", "通報を送信しました。Machi が確認します。", "Report submitted. Machi will review it.")
        } catch {
            actionMessage = error.kaixUserMessage
        }
    }
}

private struct ListingQuickInquiry: Identifiable {
    let id: String
    let title: String
    let message: String
    let details: [[String: String]]
}

private struct ListingInquiryReceipt: Identifiable {
    let id: String
    let listingTitle: String
    let listingType: String
    let inquiryType: String
    let status: String
    let successTitle: String
    let conversationId: String
    let details: [[String: String]]
    let submittedAt: Date

    init(listingTitle: String, listingType: String, receipt: KaiXListingInquiryReceiptDTO) {
        self.id = receipt.resolvedInquiryId.isEmpty ? UUID().uuidString : receipt.resolvedInquiryId
        self.listingTitle = listingTitle
        self.listingType = listingType
        self.inquiryType = receipt.type ?? "general_consult"
        self.status = receipt.status ?? "submitted"
        self.successTitle = receipt.resolvedSuccessTitle
        self.conversationId = receipt.resolvedConversationId
        self.details = receipt.details ?? []
        self.submittedAt = Date()
    }

    func recordLabel(_ language: AppLanguage) -> String {
        if inquiryType == "job_apply" || inquiryType == "rental_application" {
            return KXListingCopy.pickText(language, "查看我的申请", "自分の応募を見る", "View my applications")
        }
        if inquiryType.hasSuffix("_booking") || inquiryType == "rental_viewing" {
            return KXListingCopy.pickText(language, "查看我的预约", "自分の予約を見る", "View my bookings")
        }
        return KXListingCopy.pickText(language, "查看我的咨询", "自分の問い合わせを見る", "View my inquiries")
    }
}

private struct ListingInquirySuccessSheet: View {
    @Environment(\.appLanguage) private var language
    let receipt: ListingInquiryReceipt
    let onOpenRecords: () -> Void
    let onOpenConversation: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: KXSpacing.md) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title.weight(.black))
                        .foregroundStyle(KXColor.accent)
                        .frame(width: 52, height: 52)
                        .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        Text(receipt.successTitle)
                            .font(.title3.weight(.black))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(KXListingCopy.pickText(
                            language,
                            "记录已进入工作台，私信只作为后续沟通补充。",
                            "記録はワークベンチに保存されました。メッセージは補足連絡用です。",
                            "The record is saved to your workbench; messages are only for follow-up."
                        ))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("close", language))
                }

            VStack(alignment: .leading, spacing: 10) {
                receiptLine(KXListingCopy.pickText(language, "信息", "投稿", "Listing"), receipt.listingTitle)
                receiptLine(KXListingCopy.pickText(language, "类型", "種類", "Type"), Self.typeLabel(receipt.inquiryType, language))
                receiptLine(KXListingCopy.pickText(language, "状态", "ステータス", "Status"), Self.statusLabel(receipt.status, language))
                receiptLine(KXListingCopy.pickText(language, "时间", "日時", "Time"), Self.timeLabel(receipt.submittedAt, language))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.softBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !receipt.details.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    Text(KXListingCopy.pickText(language, "提交摘要", "送信内容", "Submission summary"))
                        .font(.subheadline.weight(.black))
                    ForEach(Array(receipt.details.prefix(8).enumerated()), id: \.offset) { _, item in
                        let label = ListingIntakeLocalizer.text(item["label"] ?? "", language)
                        let value = item["value"] ?? ""
                        if !label.isEmpty || !value.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.sm) {
                                Text(label)
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 86, alignment: .leading)
                                Text(value)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KXColor.softBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(KXColor.separator.opacity(0.5), lineWidth: 0.7)
                }
            }

                VStack(spacing: 10) {
                    Button(action: onOpenRecords) {
                        Label(receipt.recordLabel(language), systemImage: "tray.full")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(KXColor.accent, in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)

                    Button(action: onOpenConversation) {
                        Label(
                            KXListingCopy.pickText(language, "继续私信补充", "補足メッセージを送る", "Continue follow-up message"),
                            systemImage: "bubble.left.and.bubble.right"
                        )
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(KXColor.softBackground, in: Capsule())
                            .foregroundStyle(receipt.conversationId.isEmpty ? .secondary : KXColor.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(receipt.conversationId.isEmpty)

                    Button(action: onClose) {
                        Text(KXListingCopy.pickText(language, "返回详情", "詳細へ戻る", "Back to detail"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(KaiXTheme.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kxPageBackground()
    }

    private func receiptLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func typeLabel(_ type: String, _ language: AppLanguage) -> String {
        switch type {
        case "secondhand_trade_request", "secondhand_consult": KXListingCopy.pickText(language, "二手交易咨询", "フリマ取引相談", "Marketplace inquiry")
        case "rental_viewing": KXListingCopy.pickText(language, "看房预约", "内見予約", "Viewing request")
        case "rental_application": KXListingCopy.pickText(language, "租房申请", "賃貸申込", "Rental application")
        case "job_apply": KXListingCopy.pickText(language, "职位申请", "求人応募", "Job application")
        case "restaurant_booking": KXListingCopy.pickText(language, "餐饮订座", "飲食予約", "Restaurant booking")
        case "stay_booking": KXListingCopy.pickText(language, "住宿预订", "宿泊予約", "Stay booking")
        case "travel_ticket_booking": KXListingCopy.pickText(language, "旅行票务", "旅行・チケット予約", "Travel/ticket booking")
        case "transfer_booking": KXListingCopy.pickText(language, "接送预约", "送迎予約", "Transfer booking")
        case "paperwork_booking": KXListingCopy.pickText(language, "手续协助", "手続きサポート", "Paperwork help")
        case "moving_cleaning_booking": KXListingCopy.pickText(language, "搬家清洁", "引越し・清掃", "Moving/cleaning")
        case "life_setup_booking": KXListingCopy.pickText(language, "生活开通", "生活セットアップ", "Life setup")
        case "beauty_health_booking": KXListingCopy.pickText(language, "美容健康", "美容・健康", "Beauty/health")
        case "pet_family_booking": KXListingCopy.pickText(language, "宠物家庭", "ペット・家庭", "Pet/family")
        case "discount_claim": KXListingCopy.pickText(language, "优惠咨询", "特典問い合わせ", "Deal inquiry")
        default: KXListingCopy.pickText(language, "城市咨询", "街の問い合わせ", "City inquiry")
        }
    }

    private static func statusLabel(_ status: String, _ language: AppLanguage) -> String {
        switch status {
        case "submitted": KXListingCopy.pickText(language, "已提交", "送信済み", "Submitted")
        case "reviewing": KXListingCopy.pickText(language, "处理中", "対応中", "Reviewing")
        case "contacted": KXListingCopy.pickText(language, "已联系", "連絡済み", "Contacted")
        case "confirmed": KXListingCopy.pickText(language, "已确认", "確定済み", "Confirmed")
        case "rescheduled": KXListingCopy.pickText(language, "待改期", "日程調整中", "Rescheduling")
        case "rejected": KXListingCopy.pickText(language, "已拒绝", "却下", "Rejected")
        case "withdrawn": KXListingCopy.pickText(language, "已撤回", "取り下げ", "Withdrawn")
        case "completed": KXListingCopy.pickText(language, "已完成", "完了", "Completed")
        case "closed": KXListingCopy.pickText(language, "已关闭", "終了", "Closed")
        default: KXListingCopy.pickText(language, "新提交", "新規送信", "New")
        }
    }

    // Cached per-locale: DateFormatter construction is expensive, and this
    // label re-renders with the receipt sheet. Fixed format ("yyyy-MM-dd
    // HH:mm"), so the cached instance produces byte-identical output.
    private static var timeLabelFormatters: [String: DateFormatter] = [:]

    private static func timeLabel(_ date: Date, _ language: AppLanguage) -> String {
        let localeID = language == .ja ? "ja_JP" : language == .en ? "en_US" : "zh_CN"
        let formatter: DateFormatter
        if let cached = timeLabelFormatters[localeID] {
            formatter = cached
        } else {
            let made = DateFormatter()
            made.locale = Locale(identifier: localeID)
            made.dateFormat = "yyyy-MM-dd HH:mm"
            timeLabelFormatters[localeID] = made
            formatter = made
        }
        return formatter.string(from: date)
    }
}

enum ListingIntakeLocalizer {
    static func text(_ value: String, _ language: AppLanguage) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return value }
        if let entry = table[normalized] {
            return KXListingCopy.pickText(language, normalized, entry.ja, entry.en)
        }
        return KXListingCopy.attributeLabel(normalized, language)
    }

    static func requiredMessage(_ fieldLabel: String, _ language: AppLanguage) -> String {
        let label = text(fieldLabel, language)
        return KXListingCopy.pickText(language, "请填写「\(label)」", "「\(label)」を入力してください", "Please fill in \"\(label)\"")
    }

    private static let table: [String: (ja: String, en: String)] = [
        "预订住宿": ("宿泊を予約", "Book stay"),
        "在线订座": ("席を予約", "Reserve table"),
        "订座": ("席を予約", "reserve a table"),
        "预订门票": ("チケットを予約", "Book tickets"),
        "预订行程": ("ツアーを予約", "Book tour"),
        "预订": ("予約", "Book"),
        "预约接送": ("送迎を予約", "Book transfer"),
        "预约手续协助": ("手続きサポートを予約", "Book paperwork help"),
        "预约搬家清洁": ("引越し・清掃を予約", "Book moving/cleaning"),
        "预约生活开通": ("生活セットアップを予約", "Book life setup"),
        "预约服务": ("サービスを予約", "Book service"),
        "预约美容健康": ("美容・健康を予約", "book beauty/health"),
        "预约看房": ("内見を予約", "Request viewing"),
        "申请职位": ("求人に応募", "Apply for job"),
        "申请": ("応募", "Apply"),
        "联系商家": ("店舗に問い合わせ", "Contact merchant"),
        "报名 / 咨询": ("申込 / 問い合わせ", "Join / inquire"),
        "联系卖家": ("出品者に問い合わせ", "Contact seller"),
        "咨询": ("問い合わせ", "inquire"),
        "补充说明（选填）": ("補足（任意）", "Additional details (optional)"),
        "提交后会生成正式记录，私信只用于后续补充沟通。Machi 不代收交易款、押金、保证金或第三方服务款，请勿提前转账。": ("送信後は正式な記録が作成され、メッセージは補足連絡用です。Machi は代金・保証金・第三者サービス費を預かりません。前払いは避けてください。", "Submitting creates an official record; messages are only for follow-up. Machi does not hold trade payments, deposits, guarantees, or third-party service fees. Avoid paying in advance."),
        "提交中": ("送信中", "Submitting"),
        "关闭": ("閉じる", "Close"),
        "请选择": ("選択してください", "Select"),
        "希望看房日期": ("希望内見日", "Preferred viewing date"),
        "希望时段": ("希望時間帯", "Preferred time"),
        "当前情况": ("現在の状況", "Current situation"),
        "入住人数": ("宿泊・入居人数", "People"),
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

enum ListingFilterLocalizer {
    static func text(_ value: String, _ language: AppLanguage) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return value }
        if let entry = table[normalized] {
            return KXListingCopy.pickText(language, normalized, entry.ja, entry.en)
        }
        let category = KXListingCopy.categoryLabel(normalized, language)
        if category != normalized { return category }
        return ListingIntakeLocalizer.text(normalized, language)
    }

    private static let table: [String: (ja: String, en: String)] = [
        "每晚价格": ("1泊料金", "Nightly price"),
        "月租范围": ("月額家賃", "Monthly rent"),
        "薪资范围": ("給与範囲", "Pay range"),
        "价格范围": ("価格範囲", "Price range"),
        "最低": ("下限", "Min"),
        "最高": ("上限", "Max"),
        "不限": ("指定なし", "Any"),
        "出售": ("売ります", "For sale"),
        "全新": ("新品", "Brand new"),
        "几乎全新": ("ほぼ新品", "Like new"),
        "良好": ("良好", "Good"),
        "有使用痕迹": ("使用感あり", "Used"),
        "可用": ("使用可", "Fair"),
        "面交": ("手渡し", "Meetup"),
        "自取": ("引き取り", "Pickup"),
        "邮寄": ("配送", "Shipping"),
        "可商量": ("相談可", "Negotiable"),
        "交易偏好": ("取引条件", "Deal preferences"),
        "可自取": ("引き取り可", "Pickup available"),
        "可邮寄": ("配送可", "Shipping available"),
        "2 人及以上": ("2名以上", "2+ guests"),
        "3 人及以上": ("3名以上", "3+ guests"),
        "4 人及以上": ("4名以上", "4+ guests"),
        "6 人及以上": ("6名以上", "6+ guests"),
        "住宿条件": ("宿泊条件", "Stay options"),
        "条件": ("条件", "Options"),
        "可宠物": ("ペット可", "Pet friendly"),
        "可短租": ("短期可", "Short-term OK"),
        "可合租": ("ルームシェア可", "Share OK"),
        "雇佣形式": ("雇用形態", "Employment type"),
        "日语要求": ("日本語条件", "Japanese requirement"),
        "日语不限": ("日本語不問", "No Japanese required"),
        "签证支持": ("ビザサポート", "Visa support"),
        "有": ("あり", "Available"),
        "可咨询": ("相談可", "Ask"),
        "可远程": ("リモート可", "Remote OK"),
        "服务细分类": ("サービス細分類", "Service subcategory"),
        "餐饮预约": ("飲食店", "Restaurants"),
        "餐厅美食": ("飲食店", "Restaurants"),
        "餐厅": ("飲食店", "Restaurants"),
        "旅行票务": ("旅行・チケット", "Travel"),
        "接送交通": ("送迎・交通", "Transfers"),
        "美容健康": ("美容・健康", "Beauty & health"),
        "商家条件": ("店舗条件", "Merchant options"),
        "需要预约": ("予約必須", "Booking required"),
        "城市范围": ("都市圏", "Metro area"),
        "热门城市": ("人気都市", "Popular cities")
    ]
}

private struct ListingIntakeField: Identifiable, Equatable {
    let id: String
    let label: String
    let placeholder: String
    let options: [String]
    let required: Bool
    /// Renders a calendar DatePicker (no past dates) instead of free text, so
    /// viewing / booking dates are picked, never mistyped.
    let isDate: Bool

    init(_ id: String, label: String, placeholder: String = "", options: [String] = [], required: Bool = false, isDate: Bool = false) {
        self.id = id
        self.label = label
        self.placeholder = placeholder
        self.options = options
        self.required = required
        self.isDate = isDate
    }
}

private struct ListingIntakeSpec {
    let title: String
    let actionWord: String
    let noteLabel: String
    let fields: [ListingIntakeField]

    static func forType(_ type: String, category: String? = nil) -> ListingIntakeSpec {
        // 结构化预订：服务类目给出真正可用的字段。
        if type == "local_service" {
            if KXListingCopy.isStayCategory(category) {
                return ListingIntakeSpec(
                    title: "预订住宿",
                    actionWord: "预订住宿",
                    noteLabel: "特殊需求",
                    fields: [
                        ListingIntakeField("check_in", label: "入住日期", placeholder: "例如 7 月 1 日", required: true),
                        ListingIntakeField("check_out", label: "退房日期", placeholder: "例如 7 月 3 日", required: true),
                        ListingIntakeField("guests", label: "入住人数", options: ["1 人", "2 人", "3 人", "4 人", "5 人及以上"], required: true),
                        ListingIntakeField("rooms", label: "房间数", options: ["1 间", "2 间", "3 间及以上"]),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            }
            if KXListingCopy.isFoodCategory(category) {
                // 餐饮在线订座
                return ListingIntakeSpec(
                    title: "在线订座",
                    actionWord: "订座",
                    noteLabel: "备注（忌口 / 包间 / 儿童座椅等）",
                    fields: [
                        ListingIntakeField("date", label: "用餐日期", placeholder: "例如 6 月 15 日", required: true),
                        ListingIntakeField("time", label: "到店时间", options: ["午市 11:00-14:00", "下午 14:00-17:00", "晚市 17:00-20:00", "晚市 20:00 之后"], required: true),
                        ListingIntakeField("party", label: "用餐人数", options: ["1-2 人", "3-4 人", "5-8 人", "8 人以上"], required: true),
                        ListingIntakeField("name", label: "预订姓名", placeholder: "到店报姓名即可", required: true),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            }
            switch category ?? "" {
            case "景点门票", "一日游", "本地向导", "体验活动", "包车行程":
                return ListingIntakeSpec(
                    title: category == "景点门票" ? "预订门票" : "预订行程",
                    actionWord: "预订",
                    noteLabel: "补充说明",
                    fields: [
                        ListingIntakeField("date", label: "出行日期", placeholder: "例如 7 月 1 日", required: true),
                        ListingIntakeField("tickets", label: "人数 / 票数", options: ["1", "2", "3", "4", "5 及以上"], required: true),
                        ListingIntakeField("language", label: "希望语言", options: ["中文", "日本語", "English", "无要求"]),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "接送机", "机场接送", "车站接送", "包车", "行李协助":
                return ListingIntakeSpec(
                    title: "预约接送",
                    actionWord: "预约接送",
                    noteLabel: "补充说明",
                    fields: [
                        ListingIntakeField("date", label: "用车日期", placeholder: "例如 7 月 1 日", required: true),
                        ListingIntakeField("route", label: "路线", placeholder: "成田机场 -> 新宿 / 东京站 -> 住处", required: true),
                        ListingIntakeField("flight", label: "航班/车次", placeholder: "例如 NH878 / 新干线到达时间"),
                        ListingIntakeField("passengers", label: "人数", options: ["1", "2", "3", "4", "5 及以上"], required: true),
                        ListingIntakeField("luggage", label: "行李数", options: ["1-2 件", "3-4 件", "5 件及以上"]),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "材料翻译", "市役所陪同", "银行卡协助", "手机卡协助", "租房申请协助", "签证材料整理", "翻译手续", "签证/手续协助", "翻译":
                return ListingIntakeSpec(
                    title: "预约手续协助",
                    actionWord: "预约手续协助",
                    noteLabel: "具体需求",
                    fields: [
                        ListingIntakeField("service", label: "事项类型", placeholder: "住民票 / 银行卡 / 手机卡 / 材料翻译", required: true),
                        ListingIntakeField("deadline", label: "希望完成时间", placeholder: "例如 本周内 / 3 个工作日"),
                        ListingIntakeField("language", label: "希望语言", options: ["中文", "日本語", "English", "无要求"]),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "搬家", "退房清洁", "粗大垃圾协助", "行李搬运", "家具家电配送协助", "搬家清洁", "清洁":
                return ListingIntakeSpec(
                    title: "预约搬家清洁",
                    actionWord: "预约搬家清洁",
                    noteLabel: "物品/房间说明",
                    fields: [
                        ListingIntakeField("date", label: "希望日期", placeholder: "例如 7 月 1 日", required: true, isDate: true),
                        ListingIntakeField("address_area", label: "服务区域", placeholder: "新宿区 / 丰岛区", required: true),
                        ListingIntakeField("volume", label: "物品量/房型", placeholder: "1K / 纸箱 20 个 / 大件 3 件"),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "手机卡开通", "网络开通", "水电煤协助", "地址登记协助", "粗大垃圾预约", "生活跑腿":
                return ListingIntakeSpec(
                    title: "预约生活开通",
                    actionWord: "预约生活开通",
                    noteLabel: "具体需求",
                    fields: [
                        ListingIntakeField("service", label: "服务事项", placeholder: "手机卡 / 网络 / 水电煤 / 地址登记", required: true),
                        ListingIntakeField("preferred_date", label: "希望日期", placeholder: "例如 到日当天 / 本周末"),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "美容美发", "美甲", "按摩", "皮肤管理", "体检/牙科预约协助":
                return ListingIntakeSpec(
                    title: "预约服务",
                    actionWord: "预约美容健康",
                    noteLabel: "注意事项",
                    fields: [
                        ListingIntakeField("date", label: "预约日期", placeholder: "例如 6 月 20 日", required: true, isDate: true),
                        ListingIntakeField("time", label: "预约时段", options: ["上午", "下午", "晚上", "周末"], required: true),
                        ListingIntakeField("service", label: "服务项目", placeholder: "剪发 / 美甲 / 按摩 / 体检预约", required: true),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            default:
                break
            }
        }
        switch type {
        case "rental":
            return ListingIntakeSpec(
                title: "预约看房",
                actionWord: "预约看房",
                noteLabel: "备注",
                fields: [
                    ListingIntakeField("date", label: "希望看房日期", placeholder: "例如 6 月 12 日", required: true, isDate: true),
                    ListingIntakeField("time", label: "希望时段", options: ["上午", "下午", "晚上", "周末"], required: true),
                    ListingIntakeField("situation", label: "当前情况", options: ["在日本", "海外", "学生", "在职"]),
                    ListingIntakeField("move_in", label: "入住时间", placeholder: "例如 7 月上旬 / 即可入住"),
                    ListingIntakeField("people", label: "入住人数", options: ["1 人", "2 人", "3 人", "4 人及以上"]),
                    ListingIntakeField("budget", label: "预算", placeholder: "例如 月租 8 万以内"),
                    ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                ]
            )
        case "job", "hiring", "work":
            return ListingIntakeSpec(
                title: "申请职位",
                actionWord: "申请",
                noteLabel: "自我介绍",
                fields: [
                    ListingIntakeField("name", label: "姓名", required: true),
                    ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ListingIntakeField("visa", label: "签证状态", options: ["留学", "工作签证", "永住", "家族滞在", "其他"]),
                    ListingIntakeField("japanese", label: "日语水平", options: ["N1", "N2", "N3", "日常会话", "暂不会"]),
                    ListingIntakeField("availability", label: "可工作时间", placeholder: "平日晚上 / 周末"),
                    ListingIntakeField("start_date", label: "最快入职时间", placeholder: "例如 立即 / 7 月起"),
                ]
            )
        case "local_service":
            return ListingIntakeSpec(
                title: "预约服务",
                actionWord: "预约服务",
                noteLabel: "具体需求",
                fields: [
                    ListingIntakeField("city", label: "服务城市", required: true),
                    ListingIntakeField("service_scene", label: "服务场景", options: ["到店预约", "景点门票", "一日游", "机场接送", "翻译手续", "搬家清洁", "生活开通", "美容健康"]),
                    ListingIntakeField("date", label: "希望日期", placeholder: "例如 6 月 12 日", isDate: true),
                    ListingIntakeField("time", label: "希望时段", options: ["上午", "下午", "晚上", "周末"]),
                    ListingIntakeField("people", label: "人数/件数", placeholder: "例如 2 人 / 3 件行李 / 1 套资料"),
                    ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                ]
            )
        case "discount":
            return ListingIntakeSpec(title: "联系商家", actionWord: "咨询", noteLabel: "留言", fields: [
                ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
            ])
        case "event":
            return ListingIntakeSpec(title: "报名 / 咨询", actionWord: "报名 / 咨询", noteLabel: "留言", fields: [
                ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
            ])
        default:
            return ListingIntakeSpec(
                title: "联系卖家",
                actionWord: "咨询",
                noteLabel: "补充留言",
                fields: [
                    ListingIntakeField("intent", label: "咨询意向", options: ["想购买", "想议价", "想看实物", "想预约自取", "询问是否还在"], required: true),
                    ListingIntakeField("meetup", label: "希望交易地点", placeholder: "例如 新宿站 / 池袋 / 可线上确认"),
                    ListingIntakeField("available_time", label: "可交易时间", placeholder: "例如 今天晚上 / 周末下午 / 平日 19:00 后", required: true),
                    ListingIntakeField("delivery", label: "交易方式", options: ["自取 / 面交", "希望邮寄", "都可以"]),
                    ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                ]
            )
        }
    }
}

private struct ListingIntakeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    let listingTitle: String
    let listingType: String
    var listingCategory: String? = nil
    let submitting: Bool
    let onSubmit: (_ message: String, _ details: [[String: String]]) -> Void

    @State private var values: [String: String] = [:]
    @State private var note = ""
    @State private var errorMessage: String?

    private var spec: ListingIntakeSpec {
        ListingIntakeSpec.forType(listingType, category: listingCategory)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ListingIntakeLocalizer.text(spec.title, language))
                            .font(.title3.weight(.black))
                        Text(listingTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kxGlassSurface(radius: KXRadius.card)

                    ForEach(spec.fields) { field in
                        intakeField(field)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(ListingIntakeLocalizer.text(spec.noteLabel, language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField(ListingIntakeLocalizer.text("补充说明（选填）", language), text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.subheadline.weight(.semibold))
                            .padding(KXSpacing.md)
                            .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(KXSpacing.md)
                    .background(KXColor.softBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.heat)
                    }

                    Text(ListingIntakeLocalizer.text("提交后会生成正式记录，私信只用于后续补充沟通。Machi 不代收交易款、押金、保证金或第三方服务款，请勿提前转账。", language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KXColor.heat)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(KXSpacing.md)
                        .background(KXColor.heat.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button(action: submit) {
                        HStack {
                            if submitting { KXSpinner(size: 18, lineWidth: 2.2, tint: .white) }
                            Text(submitting ? ListingIntakeLocalizer.text("提交中", language) : ListingIntakeLocalizer.text(spec.title, language))
                                .font(.headline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KXColor.accent, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(submitting)
                }
                .padding(KaiXTheme.horizontalPadding)
            }
            .kxPageBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ListingIntakeLocalizer.text("关闭", language)) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func intakeField(_ field: ListingIntakeField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.required ? "\(ListingIntakeLocalizer.text(field.label, language)) *" : ListingIntakeLocalizer.text(field.label, language))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if field.isDate {
                DatePicker(
                    "",
                    selection: dateBinding(for: field),
                    in: Date()...,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .padding(.horizontal, KXSpacing.md)
                .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                // Seed the stored value so a required date validates even if the
                // user accepts the default without opening the picker.
                .onAppear {
                    if (values[field.id] ?? "").isEmpty {
                        values[field.id] = Self.intakeDateFormatter.string(from: dateBinding(for: field).wrappedValue)
                    }
                }
            } else if field.options.isEmpty {
                TextField(ListingIntakeLocalizer.text(field.placeholder.isEmpty ? field.label : field.placeholder, language), text: binding(for: field))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, KXSpacing.md)
                    .frame(minHeight: 42)
                    .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Picker(ListingIntakeLocalizer.text(field.label, language), selection: binding(for: field)) {
                    Text(ListingIntakeLocalizer.text("请选择", language)).tag("")
                    ForEach(field.options, id: \.self) { option in
                        Text(ListingIntakeLocalizer.text(option, language)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 10)
                .padding(.vertical, KXSpacing.sm)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(KXSpacing.md)
        .background(KXColor.softBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func binding(for field: ListingIntakeField) -> Binding<String> {
        Binding(
            get: { values[field.id, default: ""] },
            set: { values[field.id] = $0 }
        )
    }

    /// Stable, parseable storage format for picked dates (shown back in 我的咨询).
    private static let intakeDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func dateBinding(for field: ListingIntakeField) -> Binding<Date> {
        Binding(
            get: {
                if let raw = values[field.id], let parsed = Self.intakeDateFormatter.date(from: raw) {
                    return parsed
                }
                return Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            },
            set: { values[field.id] = Self.intakeDateFormatter.string(from: $0) }
        )
    }

    private func submit() {
        for field in spec.fields where field.required {
            if values[field.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = ListingIntakeLocalizer.requiredMessage(field.label, language)
                return
            }
        }
        errorMessage = nil
        let details = spec.fields.compactMap { field -> [String: String]? in
            let value = values[field.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return ["label": ListingIntakeLocalizer.text(field.label, language), "value": ListingIntakeLocalizer.text(value, language)]
        }
        onSubmit(note, details)
    }
}

enum ListingMediaUploadPhase: Equatable {
    case idle
    case preparing
    case uploading(Double)
    case completing
    case ready
    case failed(String)

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .idle: return KXListingCopy.pickText(language, "待上传", "アップロード待ち", "Waiting")
        case .preparing: return KXListingCopy.pickText(language, "准备中", "準備中", "Preparing")
        case .uploading(let progress):
            return "\(KXListingCopy.pickText(language, "上传中", "アップロード中", "Uploading")) \(Int(progress * 100))%"
        case .completing: return KXListingCopy.pickText(language, "确认中", "確認中", "Finalizing")
        case .ready: return KXListingCopy.pickText(language, "已上传", "アップロード済み", "Uploaded")
        case .failed(let message): return message
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct ListingPublishReceipt: Identifiable {
    let id = UUID()
    let listingId: String
    let isEditing: Bool
    let published: Bool
    let typeLabel: String
    let title: String
    let regionLabel: String
    let locationText: String
}

/// Post-publish success sheet — clear confirmation with the key facts and the
/// three next actions (查看发布 / 继续发布 / 去工作台). Replaces the old 0.42s flash.
struct ListingPublishSuccessSheet: View {
    let receipt: ListingPublishReceipt
    let language: AppLanguage
    let onViewListing: () -> Void
    let onContinuePublishing: () -> Void
    let onClose: () -> Void

    private func pick(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(KXColor.softBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("close", language))
            }
            .padding(.horizontal, KXSpacing.lg)
            .padding(.top, KXSpacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    VStack(spacing: 10) {
                        Image(systemName: receipt.published ? "checkmark.seal.fill" : "clock.badge.checkmark.fill")
                            .kxScaledFont(44)
                            .foregroundStyle(receipt.published ? KXColor.accent : .orange)
                        Text(receipt.published
                             ? pick("发布成功", "公開しました", "Published")
                             : pick("已提交审核", "審査に提出しました", "Submitted for review"))
                            .font(.title3.weight(.bold))
                        Text(receipt.published
                             ? pick("已同步到 Web 与 iOS，并进入对应城市频道。", "Web と iOS に同期し、都市チャンネルに表示されます。", "Synced to web & iOS and added to the city channel.")
                             : pick("审核通过后会自动展示，可在详情页查看状态。", "承認後に自動表示されます。詳細で状態を確認できます。", "It will appear once approved; track status on the detail page."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, KXSpacing.sm)

                    VStack(spacing: 0) {
                        row(pick("类型", "種類", "Type"), receipt.typeLabel)
                        Divider()
                        row(pick("标题", "タイトル", "Title"), receipt.title)
                        if !receipt.regionLabel.isEmpty {
                            Divider(); row(pick("发布地区", "公開エリア", "Publish area"), receipt.regionLabel)
                        }
                        if !receipt.locationText.isEmpty {
                            Divider(); row(pick("展示位置", "表示する場所", "Location"), receipt.locationText)
                        }
                        Divider()
                        row(pick("状态", "状態", "Status"), receipt.published ? pick("已发布", "公開中", "Live") : pick("审核中", "審査中", "In review"))
                    }
                    .padding(KXSpacing.md)
                    .background(KXColor.softBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, KXSpacing.lg)
                .padding(.bottom, KXSpacing.md)
            }

            VStack(spacing: 10) {
                Button(action: onViewListing) {
                    Text(pick("查看发布", "投稿を見る", "View listing"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(KXColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                HStack(spacing: 10) {
                    Button(action: onContinuePublishing) {
                        Text(pick("继续发布", "続けて投稿", "Publish another"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(KXColor.accent.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button(action: onClose) {
                        Text(pick("完成", "完了", "Done"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(KXColor.softBackground.opacity(0.9), in: Capsule())
                            .overlay(Capsule().stroke(KXColor.separator.opacity(0.6), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KXSpacing.lg)
            .padding(.bottom, KXSpacing.lg)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
    }
}
