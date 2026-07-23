import SwiftUI

/// 活动详情 —— Machi 版 Luma 活动页:大图封面 + 日期块、标题区、
/// 报名卡(人数/满员/候补)、时间地点行、主办方卡、参加者头像墙、
/// 图文详情、分享(带 Web 短链)。报名字段由服务端下发,动态渲染。
struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState

    let idOrSlug: String
    let currentUser: UserEntity

    @State private var event: KaiXEventDTO?
    @State private var isLoading = true
    @State private var isRegistering = false
    /// 取消报名进行中:CTA 转圈 + 禁点,弱网下不再「点了没反应 → 连点」。
    @State private var isCancelling = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    /// 操作结果弹窗的标题(具体动作名,如「报名失败」);nil 时回落到通用「提示」。
    @State private var actionTitle: String?
    @State private var registrationOpen = false
    @State private var showCancelConfirm = false
    @State private var showDeleteConfirm = false
    /// 主办者编辑:复用 CreateEventView 预填模式(fullScreenCover,不新增路由)。
    @State private var editOpen = false
    /// 「添加到日历」:拉到 .ics 文本写临时文件后,用系统分享面板加进日历(免日历权限)。
    @State private var calendarShare: ShareableFile?
    @State private var isPreparingCalendar = false

    private var tint: Color { KXEventStyle.tint(event?.category ?? "party") }

    var body: some View {
        ZStack(alignment: .top) {
            if isLoading {
                LoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, event == nil {
                ErrorStateView(message: errorMessage) { Task { await load() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 80)
            } else if let event {
                ScrollView {
                    VStack(alignment: .leading, spacing: KXSpacing.lg) {
                        hero(event)
                        VStack(alignment: .leading, spacing: KXSpacing.lg) {
                            titleBlock(event)
                            whenWhereCard(event)
                            registrationCard(event)
                            organizerCard(event)
                            attendeesCard(event)
                            descriptionBlock(event)
                        }
                        .padding(.horizontal, KXSpacing.screen)
                    }
                    .padding(.bottom, chrome.bottomContentPadding + 96)
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .kxHidesTabBar(reason: .custom("event-detail"))
        .overlay(alignment: .top) { floatingBar }
        .overlay(alignment: .bottom) {
            if let event, !isLoading {
                bottomCTA(event)
            }
        }
        .task(id: idOrSlug) { await load() }
        .sheet(isPresented: $registrationOpen) {
            if let event {
                EventRegistrationSheet(event: event, language: language) { updated in
                    self.event = updated
                }
            }
        }
        .sheet(item: $calendarShare) { share in
            ActivityView(activityItems: [share.url])
        }
        .fullScreenCover(isPresented: $editOpen) {
            if let event {
                CreateEventView(currentUser: currentUser, editingEvent: event) { updated in
                    self.event = updated
                }
            }
        }
        .confirmationDialog(
            KXListingCopy.pickText(language, "取消报名?", "参加をキャンセルしますか?", "Cancel your registration?"),
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button(KXListingCopy.pickText(language, "取消报名", "キャンセルする", "Cancel registration"), role: .destructive) {
                Task { await cancelRegistration() }
            }
            Button(KXListingCopy.pickText(language, "再想想", "戻る", "Keep it"), role: .cancel) {}
        }
        .confirmationDialog(
            KXListingCopy.pickText(language, "删除这场活动?", "このイベントを削除しますか?", "Delete this event?"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(KXListingCopy.pickText(language, "删除活动", "削除する", "Delete"), role: .destructive) {
                Task { await deleteEvent() }
            }
            Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(KXListingCopy.pickText(language, "已报名的人会看到活动已取消,此操作不可撤销。", "参加者にはキャンセルとして表示されます。取り消せません。", "Registered people will see it cancelled. This can't be undone."))
        }
        .alert(actionTitle ?? KXListingCopy.pickText(language, "提示", "お知らせ", "Notice"), isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil; actionTitle = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
    }

    // MARK: - chrome

    private var floatingBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KXListingCopy.pickText(language, "返回", "戻る", "Back"))
            Spacer()
            if let event {
                ShareLink(item: event.webURL, subject: Text(event.title)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .background(.thinMaterial, in: Circle())
                }
                .accessibilityLabel(KXListingCopy.pickText(language, "分享", "共有", "Share"))
                // 删除权限与服务端 api_event_delete 对齐:organizer 或 role==admin。
                // 不能用 displaysOfficialBadge(徽章展示概念,含非管理员的官方/种子号),
                // 否则这些账号会看到必得 403 的删除入口。
                if event.organizer_user_id == currentUser.id || currentUser.role == .admin {
                    Menu {
                        Button {
                            editOpen = true
                        } label: {
                            Label(KXListingCopy.pickText(language, "编辑活动", "イベントを編集", "Edit event"), systemImage: "pencil")
                        }
                        Button {
                            router.open(.eventManage(idOrSlug: event.slug ?? event.id))
                        } label: {
                            Label(KXListingCopy.pickText(language, "管理报名", "参加者を管理", "Manage guests"), systemImage: "person.2.badge.gearshape")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label(KXListingCopy.pickText(language, "删除活动", "イベントを削除", "Delete event"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel(KXListingCopy.pickText(language, "更多", "その他", "More"))
                } else if event.organizer_user_id?.isEmpty == false {
                    // Apple 1.2:UGC 活动页对非主办者提供可发现的举报入口。服务端无
                    // 活动级举报端点,复用用户举报通道并在 note 里带活动上下文。
                    Menu {
                        Button(role: .destructive) {
                            reportEvent(event)
                        } label: {
                            Label(KXListingCopy.pickText(language, "举报活动", "イベントを通報", "Report event"), systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel(KXListingCopy.pickText(language, "更多", "その他", "More"))
                }
            }
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
    }

    // MARK: - sections

    private func hero(_ event: KaiXEventDTO) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = event.coverFullURL {
                    CachedMediaImageView(url: url, targetPixelSize: 1600)
                } else {
                    LinearGradient(
                        colors: [tint.opacity(0.9), tint.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: KXEventStyle.icon(event.category ?? "party"))
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(KXColor.onTint(tint).opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            if let badge = KXEventStyle.dateBadge(event.starts_at, timezone: event.timezone, language: language) {
                VStack(spacing: 0) {
                    Text(badge.month)
                        .font(.caption.weight(.black))
                        .foregroundStyle(KXColor.heat)
                    Text(badge.day)
                        .font(.title2.weight(.black))
                        .foregroundStyle(.primary)
                }
                .frame(width: 56, height: 60)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                .padding(14)
            }
        }
    }

    private func titleBlock(_ event: KaiXEventDTO) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(spacing: 6) {
                Label(KXEventStyle.label(event.category ?? "party", fallback: event.category_label, language), systemImage: KXEventStyle.icon(event.category ?? "party"))
                    .font(.caption.weight(.black))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(tint.opacity(0.12), in: Capsule())
                if event.is_featured ?? false {
                    Label(KXListingCopy.pickText(language, "Machi 精选", "Machi 注目", "Machi Featured"), systemImage: "star.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(KXColor.rankGold)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(KXColor.rankGold.opacity(0.13), in: Capsule())
                }
                if let partner = event.partner_name, !partner.isEmpty {
                    Label(partner, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(event.title)
                .font(.title2.weight(.black))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = event.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, KXSpacing.md)
    }

    private func whenWhereCard(_ event: KaiXEventDTO) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .top, spacing: KXSpacing.md) {
                Image(systemName: "calendar")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(KXEventStyle.timeLine(event.starts_at, event.ends_at, timezone: event.timezone, language: language))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(event.timezone ?? "Asia/Tokyo")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await addToCalendar(event) }
                } label: {
                    Group {
                        if isPreparingCalendar {
                            KXSpinner(size: 17, lineWidth: 2)
                        } else {
                            Image(systemName: "calendar.badge.plus")
                                .font(.title3)
                        }
                    }
                    .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .disabled(isPreparingCalendar)
                .accessibilityLabel(KXListingCopy.pickText(language, "添加到日历", "カレンダーに追加", "Add to calendar"))
            }
            if (event.venue_name?.isEmpty == false) || (event.address?.isEmpty == false) {
                HStack(alignment: .top, spacing: KXSpacing.md) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        if let venue = event.venue_name, !venue.isEmpty {
                            Text(venue)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        if let address = event.address, !address.isEmpty {
                            Text(address)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                    if let query = mapQuery(event) {
                        Button {
                            openInMaps(query)
                        } label: {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .font(.title3)
                                .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(KXListingCopy.pickText(language, "打开地图", "地図を開く", "Open in Maps"))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private func mapQuery(_ event: KaiXEventDTO) -> String? {
        let venue = event.venue_name ?? ""
        let address = event.address ?? ""
        let combined = address.isEmpty ? venue : address
        return combined.isEmpty ? nil : combined
    }

    /// .urlQueryAllowed 不转义 &/=/+/? 这类 query 结构字符:地址含「A館&B館」
    /// 会被 Maps 在 & 处截断、'+' 被当空格,导航到错误地点。这里把它们也
    /// percent-encode 掉;maps:// 打不开时回退网页版 Apple Maps,点了不再毫无反应。
    private func openInMaps(_ query: String) {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?/")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard !encoded.isEmpty, let url = URL(string: "maps://?q=\(encoded)") else { return }
        UIApplication.shared.open(url) { opened in
            guard !opened, let webURL = URL(string: "https://maps.apple.com/?q=\(encoded)") else { return }
            UIApplication.shared.open(webURL)
        }
    }

    private func registrationCard(_ event: KaiXEventDTO) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                Text(KXListingCopy.pickText(language, "报名", "参加登録", "Registration"))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                if let price = event.price_text, !price.isEmpty {
                    Text(price)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(KXColor.livingWarm)
                }
            }
            if event.viewerPending {
                Label(KXListingCopy.pickText(language, "待审核 · 主办方通过后即报名成功", "承認待ち · 主催者の承認をお待ちください", "Pending approval · the host will review you"), systemImage: "clock.badge.questionmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.livingWarm)
            } else if event.viewerGoing {
                Label(KXListingCopy.pickText(language, "你已报名这场活动", "参加予定です", "You're going"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.accent)
            } else if event.viewerWaitlisted {
                Label(KXListingCopy.pickText(language, "已进入候补名单,有空位会自动顶上", "キャンセル待ちに登録済みです", "You're on the waitlist"), systemImage: "hourglass")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.heat)
            } else if (event.capacity ?? 0) > 0 {
                let left = max(0, (event.capacity ?? 0) - event.goingCountValue)
                Text(left > 0
                     ? KXListingCopy.pickText(language, "还剩 \(left) 个名额", "残り\(left)枠", "\(left) spots left")
                     : KXListingCopy.pickText(language, "名额已满,可加入候补", "満席(キャンセル待ち可)", "Full — waitlist open"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(left > 0 ? KXColor.accent : KXColor.heat)
            } else {
                Text(KXListingCopy.pickText(language, "名额不限,来就完事了", "定員なし・お気軽にどうぞ", "Open registration"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let external = event.external_url, !external.isEmpty, let url = URL(string: external) {
                Link(destination: url) {
                    Label(KXListingCopy.pickText(language, "合作方售票/详情页", "チケット / 詳細ページ", "Tickets / partner page"), systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private func organizerCard(_ event: KaiXEventDTO) -> some View {
        Group {
            if let organizer = event.organizer {
                Button {
                    router.open(.profile(userId: organizer.id))
                } label: {
                    HStack(spacing: KXSpacing.md) {
                        KXSocialAvatar(user: organizer, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(KXListingCopy.pickText(language, "主办方", "主催者", "Hosted by"))
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.tertiary)
                            HStack(spacing: 5) {
                                Text(organizer.displayName ?? organizer.display_name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                if organizer.isVerifiedMember ?? organizer.is_verified_member ?? false {
                                    KXVerifiedBadge()
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kxGlassSurface(radius: KXRadius.lg)
                    .contentShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
                }
                .buttonStyle(KXPressableStyle(scale: 0.98))
            }
        }
    }

    @ViewBuilder
    private func attendeesCard(_ event: KaiXEventDTO) -> some View {
        if event.goingCountValue > 0 {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                Text(KXListingCopy.pickText(language, "\(event.goingCountValue) 人参加", "\(event.goingCountValue)人が参加", "\(event.goingCountValue) going"))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                KXAvatarStack(users: event.attendees_preview ?? [], totalCount: event.goingCountValue, size: 34)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxGlassSurface(radius: KXRadius.lg)
        }
    }

    @ViewBuilder
    private func descriptionBlock(_ event: KaiXEventDTO) -> some View {
        if let description = event.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                Text(KXListingCopy.pickText(language, "活动详情", "イベント詳細", "About this event"))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxGlassSurface(radius: KXRadius.lg)
        }
    }

    // MARK: - CTA

    @ViewBuilder
    private func bottomCTA(_ event: KaiXEventDTO) -> some View {
        let isOrganizer = event.organizer_user_id == currentUser.id
        let ended = (event.ends_at?.isEmpty == false ? event.ends_at : event.starts_at)
            .flatMap(KXDateParsing.parse)
            .map { $0 < Date() } ?? false
        VStack(spacing: 0) {
            if event.status == "cancelled" {
                ctaLabel(KXListingCopy.pickText(language, "活动已取消", "イベントは中止されました", "Event cancelled"), style: .disabled)
            } else if ended {
                ctaLabel(KXListingCopy.pickText(language, "活动已结束", "イベントは終了しました", "Event ended"), style: .disabled)
            } else if isOrganizer {
                Button {
                    router.open(.eventManage(idOrSlug: event.slug ?? event.id))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.badge.gearshape")
                            .font(.headline.weight(.bold))
                        Text(KXListingCopy.pickText(language, "管理报名", "参加者を管理", "Manage guests"))
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(KXColor.onTint(tint))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(tint.gradient, in: Capsule())
                    .shadow(color: tint.opacity(0.3), radius: 12, y: 5)
                }
                .buttonStyle(KXPressableStyle(scale: 0.97))
            } else if event.viewerPending {
                Button {
                    showCancelConfirm = true
                } label: {
                    ctaLabel(
                        isCancelling
                            ? KXListingCopy.pickText(language, "正在撤回…", "取消しています…", "Cancelling…")
                            : KXListingCopy.pickText(language, "待审核 · 点此撤回申请", "承認待ち · タップで取消", "Pending approval · tap to cancel"),
                        style: .secondary,
                        showsSpinner: isCancelling
                    )
                }
                .buttonStyle(KXPressableStyle(scale: 0.97))
                .disabled(isCancelling)
            } else if event.viewerGoing || event.viewerWaitlisted {
                Button {
                    showCancelConfirm = true
                } label: {
                    ctaLabel(
                        isCancelling
                            ? KXListingCopy.pickText(language, "正在取消…", "取消しています…", "Cancelling…")
                            : event.viewerGoing
                                ? KXListingCopy.pickText(language, "已报名 · 点此取消", "参加予定 · タップで取消", "Going · tap to cancel")
                                : KXListingCopy.pickText(language, "候补中 · 点此取消", "キャンセル待ち · タップで取消", "Waitlisted · tap to cancel"),
                        style: .secondary,
                        showsSpinner: isCancelling
                    )
                }
                .buttonStyle(KXPressableStyle(scale: 0.97))
                .disabled(isCancelling)
            } else {
                Button {
                    openRegistration(event)
                } label: {
                    HStack(spacing: 8) {
                        if isRegistering {
                            KXSpinner(size: 17, lineWidth: 2)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.headline.weight(.bold))
                        }
                        Text(event.is_full ?? false
                             ? KXListingCopy.pickText(language, "加入候补", "キャンセル待ちに入る", "Join waitlist")
                             : KXListingCopy.pickText(language, "报名参加", "参加する", "Register"))
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(KXColor.onTint(tint))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(tint.gradient, in: Capsule())
                    .shadow(color: tint.opacity(0.3), radius: 12, y: 5)
                }
                .buttonStyle(KXPressableStyle(scale: 0.97))
                .disabled(isRegistering)
            }
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.vertical, 10)
        .kxGlassBar()
    }

    private enum CTAStyle { case disabled, neutral, secondary }

    private func ctaLabel(_ text: String, style: CTAStyle, showsSpinner: Bool = false) -> some View {
        HStack(spacing: 8) {
            if showsSpinner {
                KXSpinner(size: 15, lineWidth: 2)
            }
            Text(text)
                .font(.headline.weight(.bold))
                .foregroundStyle(style == .secondary ? tint : .secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            style == .secondary ? tint.opacity(0.10) : Color.secondary.opacity(0.10),
            in: Capsule()
        )
    }

    // MARK: - actions

    private func openRegistration(_ event: KaiXEventDTO) {
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以报名活动。", "ログインすると参加登録できます。", "Sign in to register.")) else { return }
        if (event.form_fields ?? []).isEmpty {
            Task { await registerDirect() }
        } else {
            registrationOpen = true
        }
    }

    private func registerDirect() async {
        isRegistering = true
        defer { isRegistering = false }
        do {
            event = try await KaiXAPIClient.shared.registerForEvent(idOrSlug, answers: [:])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionTitle = KXListingCopy.pickText(language, "报名失败", "登録できませんでした", "Couldn't register")
            actionMessage = error.kaixUserMessage
        }
    }

    private func cancelRegistration() async {
        guard !isCancelling else { return }
        isCancelling = true
        defer { isCancelling = false }
        do {
            event = try await KaiXAPIClient.shared.cancelEventRegistration(idOrSlug)
        } catch {
            actionTitle = KXListingCopy.pickText(language, "取消报名失败", "キャンセルできませんでした", "Couldn't cancel")
            actionMessage = error.kaixUserMessage
        }
    }

    /// 举报活动。服务端没有活动级举报端点,复用用户举报通道(举报主办者),
    /// note 里带 event 上下文供后台定位。
    private func reportEvent(_ event: KaiXEventDTO) {
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以举报。", "ログインすると通報できます。", "Sign in to report.")) else { return }
        guard let organizerId = event.organizer_user_id, !organizerId.isEmpty else { return }
        Task {
            do {
                try await KaiXAPIClient.shared.reportUser(organizerId, reason: "other", note: "event:\(event.id) slug:\(event.slug ?? "") title:\(event.title.prefix(80))")
                actionTitle = KXListingCopy.pickText(language, "举报活动", "イベントを通報", "Report event")
                actionMessage = L("reportRecorded", language)
            } catch {
                actionTitle = KXListingCopy.pickText(language, "举报失败", "通報できませんでした", "Couldn't report")
                actionMessage = error.kaixUserMessage
            }
        }
    }

    /// 拉取服务端 .ics 文本 → 写临时文件 → 走系统分享面板加入日历。全程免日历权限
    /// (不 import EventKit),把「加进哪本日历」交给系统的 Add-to-Calendar 分享动作。
    private func addToCalendar(_ event: KaiXEventDTO) async {
        guard !isPreparingCalendar else { return }
        isPreparingCalendar = true
        defer { isPreparingCalendar = false }
        do {
            let ics = try await KaiXAPIClient.shared.eventICS(idOrSlug)
            guard !ics.isEmpty, let data = ics.data(using: .utf8) else {
                actionTitle = KXListingCopy.pickText(language, "添加到日历", "カレンダーに追加", "Add to calendar")
                actionMessage = KXListingCopy.pickText(language, "生成日历文件失败,请稍后再试", "カレンダーの作成に失敗しました", "Couldn't build the calendar file")
                return
            }
            // 文件名只保留字母数字,避免 slug 里的斜杠 / 空格生成非法路径。
            let base = (event.slug ?? event.id).replacingOccurrences(of: "/", with: "-")
            let safe = base.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted).joined()
            let name = safe.isEmpty ? "event" : safe
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("machi-\(name).ics")
            try data.write(to: url, options: .atomic)
            calendarShare = ShareableFile(url: url)
        } catch {
            actionTitle = KXListingCopy.pickText(language, "添加到日历", "カレンダーに追加", "Add to calendar")
            actionMessage = error.kaixUserMessage
        }
    }

    private func deleteEvent() async {
        do {
            try await KaiXAPIClient.shared.deleteEvent(idOrSlug)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // 通知列表页立即剔除该卡:静默合并刷新保留掉出首页的旧条目,
            // 不广播的话刚删的活动仍显示,点进去才 404。id 用详情实体的真实 id。
            let removedId = event?.id ?? idOrSlug
            NotificationCenter.default.post(name: .kaiXEventRemoved, object: nil, userInfo: ["id": removedId])
            dismiss()
        } catch {
            actionTitle = KXListingCopy.pickText(language, "删除失败", "削除できませんでした", "Couldn't delete")
            actionMessage = error.kaixUserMessage
        }
    }

    private func load() async {
        isLoading = event == nil
        errorMessage = nil
        do {
            event = try await KaiXAPIClient.shared.event(idOrSlug)
            isLoading = false
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                isLoading = false
                return
            }
            errorMessage = error.kaixUserMessage
            isLoading = false
        }
    }
}

// MARK: - 报名表单(服务端下发字段,动态渲染)

private struct EventRegistrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: KaiXEventDTO
    let language: AppLanguage
    let onRegistered: (KaiXEventDTO) -> Void

    @State private var answers: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var fields: [KaiXEventFormFieldDTO] { event.form_fields ?? [] }

    private var canSubmit: Bool {
        !isSubmitting && fields.allSatisfy { field in
            !field.isRequired || !(answers[field.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    Text(event.title)
                        .font(.headline.weight(.bold))
                    ForEach(fields) { field in
                        fieldView(field)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(KXColor.heat)
                    }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.vertical, KXSpacing.lg)
            }
            .kxPageBackground()
            .navigationTitle(KXListingCopy.pickText(language, "报名信息", "参加登録", "Registration"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            KXSpinner(size: 16, lineWidth: 2)
                        } else {
                            Text(event.is_full ?? false
                                 ? KXListingCopy.pickText(language, "加入候补", "待機する", "Waitlist")
                                 : KXListingCopy.pickText(language, "报名", "登録", "Register"))
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func fieldView(_ field: KaiXEventFormFieldDTO) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(field.label)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                if field.isRequired {
                    Text("*").font(.caption.weight(.black)).foregroundStyle(KXColor.heat)
                }
            }
            switch field.typeKey {
            case "select":
                FlowLayout(spacing: KXSpacing.sm) {
                    ForEach(field.options ?? [], id: \.self) { option in
                        let isSelected = answers[field.id] == option
                        Button {
                            answers[field.id] = isSelected ? "" : option
                        } label: {
                            Text(option)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isSelected ? KXColor.onAccent : .primary)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(isSelected ? KXColor.accent : KXColor.softBackground.opacity(0.85), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            case "checkbox":
                Toggle(isOn: Binding(
                    get: { answers[field.id] == "true" },
                    set: { answers[field.id] = $0 ? "true" : "" }
                )) {
                    Text(field.label)
                        .font(.subheadline.weight(.semibold))
                }
                .tint(KXColor.accent)
            default:
                TextField(field.label, text: Binding(
                    get: { answers[field.id] ?? "" },
                    set: { answers[field.id] = $0 }
                ), axis: .vertical)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1...4)
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, 11)
                .kxGlassSurface(radius: KXRadius.md)
            }
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let cleaned = answers.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            let updated = try await KaiXAPIClient.shared.registerForEvent(event.slug ?? event.id, answers: cleaned)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSubmitting = false
            dismiss()
            onRegistered(updated)
        } catch {
            isSubmitting = false
            errorMessage = error.kaixUserMessage
        }
    }
}

// MARK: - 分享面板(加日历用)

/// A file URL wrapped for `.sheet(item:)` — URL itself isn't Identifiable.
private struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// 极薄的 UIActivityViewController 包装:把 .ics 临时文件交给系统分享面板,
/// 用户可选「加入日历」而无需 App 申请任何日历权限。
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
