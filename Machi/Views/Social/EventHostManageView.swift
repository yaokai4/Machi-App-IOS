import SwiftUI

/// 主办方管理报名 —— Machi 版 Luma 的「Manage guests」:名单分栏(待审核 /
/// 已报名 / 候补 / 已签到)+ 逐行审核 / 转正 / 签到 / 移除,顶部还能一键群发通知。
/// 只做流程,不碰钱(Machi 从不代收费用)。权限由服务端强制(非主办方 / 管理员会 403)。
struct EventHostManageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    let idOrSlug: String
    let currentUser: UserEntity

    @State private var attendees: [KaiXEventAttendeeDTO] = []
    @State private var formFields: [KaiXEventFormFieldDTO] = []
    @State private var total = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionMessage: String?

    @State private var selectedTab: Tab = .going
    @State private var didSetInitialTab = false
    /// 正在处理中的报名(按 user id),防重复点 + 行内转圈。
    @State private var busyUserIds: Set<String> = []
    @State private var expandedUserIds: Set<String> = []

    // 群发
    @State private var broadcastText = ""
    @State private var isBroadcasting = false
    @State private var broadcastResult: String?

    enum Tab: Hashable { case pending, going, waitlist, checkedIn }

    private func pick(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .kxHidesTabBar(reason: .custom("event-manage"))
        .task(id: idOrSlug) { await load() }
        .alert(pick("提示", "お知らせ", "Notice"), isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
    }

    // MARK: - chrome

    private var header: some View {
        HStack(spacing: KXSpacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pick("返回", "戻る", "Back"))
            VStack(alignment: .leading, spacing: 2) {
                Text(pick("管理报名", "参加者を管理", "Manage guests"))
                    .font(.headline.weight(.bold))
                Text(total > 0
                     ? pick("共 \(total) 人报名", "計\(total)名", "\(total) registered")
                     : pick("报名名单", "参加者リスト", "Guest list"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pick("刷新", "更新", "Refresh"))
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.sm)
        .kxGlassBar(ignoresTopSafeArea: true)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LoadingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, attendees.isEmpty {
            ErrorStateView(message: loadError) { Task { await load() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    broadcastCard
                    tabBar
                    rosterList
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, KXSpacing.md)
                .padding(.bottom, 120)
                .kxReadableWidth(700)
            }
            .refreshable { await refresh() }
        }
    }

    // MARK: - 群发

    private var broadcastCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            sectionLabel(pick("群发通知", "一斉連絡", "Broadcast"))
            Text(pick("发给所有正式参加者(铃铛 + 推送),用于最后确认地点、变更等。",
                      "参加者全員へ(通知 + プッシュ)。集合場所や変更のお知らせに。",
                      "Reaches everyone going (bell + push) — great for location or changes."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(alignment: .bottom, spacing: KXSpacing.sm) {
                TextField(
                    pick("写点什么发给大家…", "参加者へのメッセージ…", "Message to your guests…"),
                    text: $broadcastText, axis: .vertical
                )
                .font(.subheadline.weight(.semibold))
                .lineLimit(1...4)
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, 10)
                .kxGlassSurface(radius: KXRadius.md)
                Button {
                    Task { await sendBroadcast() }
                } label: {
                    Group {
                        if isBroadcasting {
                            KXSpinner(size: 17, lineWidth: 2)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.headline.weight(.bold))
                        }
                    }
                    .foregroundStyle(canBroadcast ? KXColor.onAccent : Color.white)
                    .frame(width: 46, height: 46)
                    .background(canBroadcast ? AnyShapeStyle(KXColor.accent) : AnyShapeStyle(Color.secondary.opacity(0.4)), in: Circle())
                }
                .buttonStyle(KXPressableStyle(scale: 0.95))
                .disabled(!canBroadcast)
                .accessibilityLabel(pick("发送", "送信", "Send"))
            }
            if let broadcastResult {
                Label(broadcastResult, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private var canBroadcast: Bool {
        !isBroadcasting && !broadcastText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 分栏

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KXSpacing.sm) {
                ForEach(availableTabs, id: \.self) { tab in
                    let isSelected = tab == effectiveTab
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Text(tabTitle(tab))
                                .font(.caption.weight(.bold))
                            Text("\(roster(for: tab).count)")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(isSelected ? KXColor.onAccent : .secondary)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 20, minHeight: 18)
                                .background(isSelected ? Color.white.opacity(0.22) : KXColor.softBackground, in: Capsule())
                        }
                        .foregroundStyle(isSelected ? KXColor.onAccent : .primary)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(isSelected ? AnyShapeStyle(KXColor.accent) : AnyShapeStyle(KXColor.softBackground.opacity(0.85)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func tabTitle(_ tab: Tab) -> String {
        switch tab {
        case .pending:   return pick("待审核", "承認待ち", "Pending")
        case .going:     return pick("已报名", "参加予定", "Going")
        case .waitlist:  return pick("候补", "キャンセル待ち", "Waitlist")
        case .checkedIn: return pick("已签到", "受付済み", "Checked in")
        }
    }

    /// Pending 仅在有待审核时出现;Going / Checked-in 常驻;候补有人才显示。
    private var availableTabs: [Tab] {
        var tabs: [Tab] = []
        if !roster(for: .pending).isEmpty { tabs.append(.pending) }
        tabs.append(.going)
        if !roster(for: .waitlist).isEmpty { tabs.append(.waitlist) }
        tabs.append(.checkedIn)
        return tabs
    }

    /// selectedTab 可能因刷新后该栏消失(最后一个待审核被通过)而失效,回退到首个可用栏。
    private var effectiveTab: Tab {
        availableTabs.contains(selectedTab) ? selectedTab : (availableTabs.first ?? .going)
    }

    private func roster(for tab: Tab) -> [KaiXEventAttendeeDTO] {
        switch tab {
        case .pending:   return attendees.filter { $0.statusKey == "pending" }
        case .going:     return attendees.filter { $0.statusKey == "going" }
        case .waitlist:  return attendees.filter { $0.statusKey == "waitlist" }
        case .checkedIn: return attendees.filter { $0.statusKey == "going" && $0.isCheckedIn }
        }
    }

    // MARK: - 名单

    @ViewBuilder
    private var rosterList: some View {
        let rows = roster(for: effectiveTab)
        if rows.isEmpty {
            emptyRoster
        } else {
            LazyVStack(spacing: KXSpacing.sm) {
                ForEach(rows) { attendeeRow($0) }
            }
        }
    }

    private var emptyRoster: some View {
        VStack(spacing: KXSpacing.sm) {
            Image(systemName: "person.2")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(emptyRosterText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private var emptyRosterText: String {
        switch effectiveTab {
        case .pending:   return pick("没有待审核的报名", "承認待ちはいません", "No one waiting for approval")
        case .going:     return pick("还没有人报名,分享一下活动页吧", "まだ参加者がいません", "No guests yet — share the event")
        case .waitlist:  return pick("候补名单是空的", "キャンセル待ちはいません", "The waitlist is empty")
        case .checkedIn: return pick("还没有人签到", "受付済みの方はいません", "No one has checked in yet")
        }
    }

    private func attendeeRow(_ att: KaiXEventAttendeeDTO) -> some View {
        let uid = att.id
        let busy = busyUserIds.contains(uid)
        let answers = orderedAnswers(att)
        let expanded = expandedUserIds.contains(uid)
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(spacing: KXSpacing.md) {
                KXSocialAvatar(user: att.user, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(att))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    rowCaption(att)
                }
                Spacer(minLength: 8)
                if busy {
                    KXSpinner(size: 18, lineWidth: 2)
                } else {
                    rowActions(att)
                }
            }
            if !answers.isEmpty {
                Button {
                    toggleExpanded(uid)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                        Text(pick("报名信息", "回答内容", "Answers"))
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(answers.enumerated()), id: \.offset) { _, pair in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pair.label)
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(.tertiary)
                                Text(pair.value)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    @ViewBuilder
    private func rowActions(_ att: KaiXEventAttendeeDTO) -> some View {
        HStack(spacing: 8) {
            switch att.statusKey {
            case "pending":
                actionChip(pick("通过", "承認", "Approve"), icon: "checkmark", tint: KXColor.accent, filled: true) {
                    await run(att.id) { _ = try await KaiXAPIClient.shared.approveRegistration(idOrSlug, userId: att.id) }
                }
                actionChip(pick("拒绝", "却下", "Decline"), icon: "xmark", tint: KXColor.heat, filled: false) {
                    await run(att.id) { _ = try await KaiXAPIClient.shared.declineRegistration(idOrSlug, userId: att.id) }
                }
            case "waitlist":
                actionChip(pick("转正", "繰り上げ", "Move up"), icon: "arrow.up", tint: KXColor.accent, filled: true) {
                    await run(att.id) { _ = try await KaiXAPIClient.shared.approveRegistration(idOrSlug, userId: att.id) }
                }
                overflowMenu(att)
            default: // going(含已签到)
                actionChip(
                    att.isCheckedIn ? pick("已签到", "受付済み", "Checked in") : pick("签到", "受付", "Check in"),
                    icon: att.isCheckedIn ? "checkmark.circle.fill" : "circle",
                    tint: KXColor.accent,
                    filled: att.isCheckedIn
                ) {
                    await run(att.id) { try await KaiXAPIClient.shared.checkInAttendee(idOrSlug, userId: att.id, checkedIn: !att.isCheckedIn) }
                }
                overflowMenu(att)
            }
        }
    }

    private func actionChip(_ title: String, icon: String, tint: Color, filled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2.weight(.bold))
                Text(title).font(.caption.weight(.bold))
            }
            .foregroundStyle(filled ? KXColor.onAccent : tint)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12)), in: Capsule())
        }
        .buttonStyle(KXPressableStyle(scale: 0.96))
    }

    private func overflowMenu(_ att: KaiXEventAttendeeDTO) -> some View {
        Menu {
            Button(role: .destructive) {
                Task { await run(att.id) { _ = try await KaiXAPIClient.shared.declineRegistration(idOrSlug, userId: att.id) } }
            } label: {
                Label(pick("移除参加者", "参加者を削除", "Remove"), systemImage: "person.badge.minus")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(KXColor.softBackground.opacity(0.7), in: Circle())
        }
    }

    // MARK: - helpers

    private func displayName(_ att: KaiXEventAttendeeDTO) -> String {
        let name = (att.user?.displayName ?? att.user?.display_name ?? "").trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        return att.user_id ?? pick("参加者", "参加者", "Guest")
    }

    @ViewBuilder
    private func rowCaption(_ att: KaiXEventAttendeeDTO) -> some View {
        switch att.statusKey {
        case "pending":
            Text(pick("等待你的通过", "承認待ち", "Awaiting approval"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(KXColor.livingWarm)
        case "waitlist":
            Text(pick("候补中", "キャンセル待ち", "On the waitlist"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(KXColor.heat)
        default:
            if att.isCheckedIn {
                Label(pick("已到场", "受付済み", "Checked in"), systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KXColor.accent)
            } else {
                Text(pick("已报名", "参加予定", "Going"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 按表单字段顺序展开答案(label: value),额外的非字段键兜底追加。
    private func orderedAnswers(_ att: KaiXEventAttendeeDTO) -> [(label: String, value: String)] {
        guard let answers = att.answers, !answers.isEmpty else { return [] }
        var used = Set<String>()
        var out: [(label: String, value: String)] = []
        for field in formFields {
            if let value = answers[field.id], !value.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append((field.label, value))
                used.insert(field.id)
            }
        }
        for (key, value) in answers where !used.contains(key) && !value.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append((key, value))
        }
        return out
    }

    private func toggleExpanded(_ uid: String) {
        if expandedUserIds.contains(uid) {
            expandedUserIds.remove(uid)
        } else {
            expandedUserIds.insert(uid)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.black))
            .foregroundStyle(.secondary)
    }

    // MARK: - actions

    private func load() async {
        isLoading = attendees.isEmpty
        loadError = nil
        do {
            let page = try await KaiXAPIClient.shared.eventAttendees(idOrSlug)
            attendees = page.items
            formFields = page.formFields
            total = page.total
            isLoading = false
            if !didSetInitialTab {
                selectedTab = roster(for: .pending).isEmpty ? .going : .pending
                didSetInitialTab = true
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                isLoading = false
                return
            }
            loadError = error.kaixUserMessage
            isLoading = false
        }
    }

    /// 静默刷新:每次操作后重拉名单,不闪整页 loading/error。
    private func refresh() async {
        do {
            let page = try await KaiXAPIClient.shared.eventAttendees(idOrSlug)
            attendees = page.items
            formFields = page.formFields
            total = page.total
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            actionMessage = error.kaixUserMessage
        }
    }

    private func run(_ userId: String, _ op: @escaping () async throws -> Void) async {
        guard !userId.isEmpty, !busyUserIds.contains(userId) else { return }
        busyUserIds.insert(userId)
        do {
            try await op()
            await refresh()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionMessage = error.kaixUserMessage
        }
        busyUserIds.remove(userId)
    }

    private func sendBroadcast() async {
        let message = broadcastText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isBroadcasting else { return }
        isBroadcasting = true
        defer { isBroadcasting = false }
        do {
            let sent = try await KaiXAPIClient.shared.broadcastEvent(idOrSlug, message: message)
            broadcastText = ""
            broadcastResult = pick("已发送给 \(sent) 人", "\(sent)名に送信しました", "Sent to \(sent) \(sent == 1 ? "person" : "people")")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            broadcastResult = nil
            actionMessage = error.kaixUserMessage
        }
    }
}
