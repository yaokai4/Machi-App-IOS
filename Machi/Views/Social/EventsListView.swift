import SwiftUI

// MARK: - 社交模块共享 DateFormatter 缓存

/// 约局/活动的列表卡在滚动热路径上逐卡格式化时间;DateFormatter 构建做
/// ICU/calendar setup、开销可观(见 ServerEntityFactory 里 KXDateParsing 的注释),
/// 必须构建一次复用。key = 模板(或固定格式)|语言|时区。项目默认 MainActor
/// 隔离,SwiftUI body 内访问安全。
enum KXSocialDateFormatters {
    private static var cache: [String: DateFormatter] = [:]

    private static func locale(for language: AppLanguage) -> Locale {
        Locale(identifier: language == .ja ? "ja_JP" : (language == .en ? "en_US" : "zh_CN"))
    }

    /// setLocalizedDateFormatFromTemplate 版(ICU 模板解析最贵,更要缓存)。
    static func templated(_ template: String, language: AppLanguage, timeZone: TimeZone = .current) -> DateFormatter {
        let key = "t|\(template)|\(language.rawValue)|\(timeZone.identifier)"
        if let cached = cache[key] { return cached }
        let f = DateFormatter()
        f.locale = locale(for: language)
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        cache[key] = f
        return f
    }

    /// dateFormat 固定格式版。
    static func fixed(_ format: String, language: AppLanguage, timeZone: TimeZone = .current) -> DateFormatter {
        let key = "f|\(format)|\(language.rawValue)|\(timeZone.identifier)"
        if let cached = cache[key] { return cached }
        let f = DateFormatter()
        f.locale = locale(for: language)
        f.timeZone = timeZone
        f.dateFormat = format
        cache[key] = f
        return f
    }
}

// MARK: - 活动样式速查

/// 活动 = 正式策划活动。分类按「活动的形式」(名词,你去参加的东西),与约局
/// (按「一起做什么」的搭子动作)彻底区分。含旧数据别名兼容。
enum KXEventStyle {
    /// 旧 key(0708 首发)→新 key,与后端 _EVENT_CATEGORY_ALIASES 对齐。
    static func canonical(_ raw: String) -> String {
        switch raw {
        case "art": "exhibition"
        case "music": "show"
        case "food", "drinks", "social": "party"
        default: raw
        }
    }

    /// 现役分类顺序(供筛选/选择器)。
    static let orderedKeys = ["exhibition", "show", "talk", "workshop", "market", "party", "sports", "reading", "film", "outdoor"]

    static func icon(_ key: String) -> String {
        switch canonical(key) {
        case "exhibition": "paintpalette.fill"
        case "show": "music.note"
        case "talk": "person.wave.2.fill"
        case "workshop": "hammer.fill"
        case "market": "bag.fill"
        case "party": "party.popper.fill"
        case "sports": "sportscourt.fill"
        case "reading": "book.fill"
        case "film": "film.fill"
        case "outdoor": "mountain.2.fill"
        default: "sparkles"
        }
    }

    /// 显式表取 KXColor trait-aware 语义色(rank 系 + chart 扩展色):同类目
    /// 色彩稳定、暗色模式提亮一档仍可读;原先的原生 .purple/.indigo… 彩虹在
    /// 暗色下不成体系且与全局调色板脱节。
    static func tint(_ key: String) -> Color {
        switch canonical(key) {
        case "exhibition": KXColor.rankViolet
        case "show": KXColor.rankVioletGlow
        case "talk": KXColor.rankSky
        case "workshop": KXColor.rankGold
        case "market": KXColor.livingWarm
        case "party": KXColor.chartPink
        case "sports": KXColor.rankTeal
        case "reading": KXColor.chartSlate
        case "film": KXColor.rankCoral
        case "outdoor": KXColor.chartGreen
        default: KXColor.categoryNeutral
        }
    }

    static func label(_ key: String, fallback: String?, _ language: AppLanguage) -> String {
        let table: [String: (zh: String, ja: String, en: String)] = [
            "exhibition": ("展览", "展示", "Exhibition"),
            "show": ("演出", "ライブ", "Show"),
            "talk": ("讲座沙龙", "トーク", "Talk"),
            "workshop": ("工作坊", "ワークショップ", "Workshop"),
            "market": ("市集", "マルシェ", "Market"),
            "party": ("派对", "パーティー", "Party"),
            "sports": ("运动赛事", "スポーツ", "Sports"),
            "reading": ("读书会", "読書会", "Reading"),
            "film": ("观影", "上映", "Film"),
            "outdoor": ("户外", "アウトドア", "Outdoor"),
            "other": ("其他", "その他", "Other"),
        ]
        if let entry = table[canonical(key)] {
            return KXListingCopy.pickText(language, entry.zh, entry.ja, entry.en)
        }
        return fallback ?? key
    }

    /// 服务端 starts_at 是 UTC 瞬时、活动页时间行下方标注 event.timezone(服务端
    /// 默认恒为 Asia/Tokyo);渲染必须用同一时区,否则设备时区≠JST 的用户(回国
    /// 探亲/来日前规划)会看到「18:00 / Asia/Tokyo」实为 19:00 JST 的错误墙钟。
    static func displayTimeZone(_ raw: String?) -> TimeZone {
        TimeZone(identifier: raw ?? "Asia/Tokyo") ?? TimeZone(identifier: "Asia/Tokyo") ?? .current
    }

    /// Luma 式日期块:「7月」+「12」两行。
    static func dateBadge(_ raw: String?, timezone: String?, language: AppLanguage) -> (month: String, day: String)? {
        guard let raw, let date = KXDateParsing.parse(raw) else { return nil }
        let tz = displayTimeZone(timezone)
        let monthFormatter = KXSocialDateFormatters.templated("MMM", language: language, timeZone: tz)
        let dayFormatter = KXSocialDateFormatters.fixed("d", language: language, timeZone: tz)
        return (monthFormatter.string(from: date), dayFormatter.string(from: date))
    }

    static func timeLine(_ startRaw: String?, _ endRaw: String?, timezone: String?, language: AppLanguage) -> String {
        guard let startRaw, let start = KXDateParsing.parse(startRaw) else { return startRaw ?? "" }
        let tz = displayTimeZone(timezone)
        let dayFormatter = KXSocialDateFormatters.templated("MMMdEEE", language: language, timeZone: tz)
        let timeFormatter = KXSocialDateFormatters.fixed("HH:mm", language: language, timeZone: tz)
        var line = "\(dayFormatter.string(from: start)) \(timeFormatter.string(from: start))"
        if let endRaw, let end = KXDateParsing.parse(endRaw) {
            line += " – \(timeFormatter.string(from: end))"
        }
        return line
    }
}

// MARK: - 活动列表(Machi 版 Luma 首页)

struct EventsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState

    let currentUser: UserEntity

    @State private var items: [KaiXEventDTO] = []
    @State private var categories: [KaiXEventCategoryDTO] = []
    @State private var total = 0
    @State private var nextOffset: Int?
    @State private var selectedCategory = ""
    @State private var when = "upcoming"
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var loadGeneration = 0
    /// loadMore 瞬时失败标记:保留 nextOffset 给内联重试,而不是静默终结分页。
    @State private var loadMoreFailed = false
    /// 已成功整表加载过的筛选组合;pop 回来 task 重启时据此走静默刷新而非整表重置。
    @State private var loadedFilterKey: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            filterRail
            ScrollView {
                LazyVStack(spacing: KXSpacing.lg) {
                    stateContent
                    if !isLoading, errorMessage == nil, nextOffset != nil {
                        if loadMoreFailed {
                            // 失败不打死分页:点一下重新挂载 loader,其 .task 会再次 loadMore。
                            Button {
                                loadMoreFailed = false
                            } label: {
                                Text(KXListingCopy.pickText(language, "加载失败,点此重试", "読み込みに失敗しました。タップして再試行", "Couldn't load more — tap to retry"))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(KXColor.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        } else {
                            KXInlineLoader()
                                .task(id: "\(items.count)|\(nextOffset ?? -1)") { await loadMore() }
                        }
                    }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, KXSpacing.sm)
                .padding(.bottom, chrome.bottomContentPadding + 84)
                .kxReadableWidth(700)
            }
            .refreshable { await load() }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottomTrailing) {
            createButton
                .padding(.trailing, KXSpacing.screen)
                .padding(.bottom, chrome.bottomContentPadding + 18)
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXEventRemoved)) { note in
            // 详情页删除活动后精确剔除该卡:refreshSilently 的分页保留策略不会
            // 删除掉出首页的条目,靠这条广播定向移除,避免留死卡点进去 404。
            guard let id = note.userInfo?["id"] as? String else { return }
            items.removeAll { $0.id == id }
            total = max(0, total - 1)
        }
        .task(id: "\(selectedCategory)|\(when)") {
            // NavigationStack 里 push 详情再 pop 回来,.task 会以相同 id 重启:
            // 此时只做静默合并刷新,保留 loadMore 累积的分页与滚动位置;
            // 只有筛选真正变化(或首载/上次失败)才整表重载。
            if loadedFilterKey == "\(selectedCategory)|\(when)", !items.isEmpty {
                await refreshSilently()
            } else {
                await load()
            }
        }
    }

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
            .accessibilityLabel(KXListingCopy.pickText(language, "返回", "戻る", "Back"))
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(KXListingCopy.pickText(language, "活动", "イベント", "Events"))
                    .font(.headline.weight(.bold))
                Text(KXListingCopy.pickText(language, "线下见面,认识新朋友", "オフラインで新しい出会いを", "Meet people in real life"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $when) {
                Text(KXListingCopy.pickText(language, "即将开始", "これから", "Upcoming")).tag("upcoming")
                Text(KXListingCopy.pickText(language, "往期", "過去", "Past")).tag("past")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.sm)
        .kxGlassBar(ignoresTopSafeArea: true)
    }

    private var filterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KXSpacing.sm) {
                categoryChip(key: "", label: KXListingCopy.pickText(language, "全部", "すべて", "All"), icon: "square.grid.2x2")
                ForEach(displayCategories) { category in
                    categoryChip(key: category.key, label: KXEventStyle.label(category.key, fallback: category.label, language), icon: KXEventStyle.icon(category.key))
                }
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.vertical, 9)
        }
    }

    private var displayCategories: [KaiXEventCategoryDTO] {
        if !categories.isEmpty { return categories }
        return KXEventStyle.orderedKeys.map {
            KaiXEventCategoryDTO(key: $0, label: $0)
        }
    }

    private func categoryChip(key: String, label: String, icon: String) -> some View {
        let isSelected = selectedCategory == key
        let tint = key.isEmpty ? KXColor.accent : KXEventStyle.tint(key)
        return Button {
            selectedCategory = key
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                Text(label)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? KXColor.onTint(tint) : tint)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isSelected ? tint : tint.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(isSelected ? 0 : 0.22), lineWidth: 0.7))
        }
        .buttonStyle(KXPressableStyle(scale: 0.95))
    }

    @ViewBuilder
    private var stateContent: some View {
        if isLoading {
            VStack(spacing: KXSpacing.lg) {
                ForEach(0..<2, id: \.self) { _ in KXBigPhotoSkeletonCard() }
            }
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) { Task { await load() } }
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if items.isEmpty {
            VStack(spacing: 18) {
                EmptyStateView(
                    title: when == "past"
                        ? KXListingCopy.pickText(language, "还没有往期活动", "過去のイベントはありません", "No past events")
                        : KXListingCopy.pickText(language, "还没有即将开始的活动", "まだイベントがありません", "No upcoming events yet"),
                    subtitle: KXListingCopy.pickText(language, "第一个把活动办起来的人就是你", "最初のイベントを作ってみましょう", "Be the first to host one"),
                    systemImage: "calendar.badge.plus"
                )
                Button {
                    openCreate()
                } label: {
                    Label(KXListingCopy.pickText(language, "创建活动", "イベントを作成", "Create event"), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.onAccent)
                        .padding(.horizontal, 22)
                        .frame(height: 48)
                        .background(KXColor.accent, in: Capsule())
                        .shadow(color: KXColor.accent.opacity(0.25), radius: 12, y: 5)
                }
                .buttonStyle(KXPressableStyle())
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            ForEach(items) { event in
                EventCard(event: event, language: language) {
                    router.open(.eventDetail(idOrSlug: event.slug ?? event.id))
                }
            }
        }
    }

    private var createButton: some View {
        Button {
            openCreate()
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .foregroundStyle(KXColor.onAccent)
                .frame(width: 56, height: 56)
                .background(KXColor.accent.gradient, in: Circle())
                .shadow(color: KXColor.accent.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(KXPressableStyle(scale: 0.92))
        .accessibilityLabel(KXListingCopy.pickText(language, "创建活动", "イベントを作成", "Create event"))
    }

    private func openCreate() {
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以创建活动。", "ログインするとイベントを作れます。", "Sign in to create an event.")) else { return }
        router.open(.createEvent)
    }

    private func load() async {
        isLoading = items.isEmpty
        loadGeneration += 1
        let generation = loadGeneration
        let filterKey = "\(selectedCategory)|\(when)"
        errorMessage = nil
        do {
            let page = try await KaiXAPIClient.shared.events(
                countryCode: RegionStore.shared.current?.countryCode ?? "jp",
                category: selectedCategory.isEmpty ? nil : selectedCategory,
                when: when
            )
            guard generation == loadGeneration else { return }
            items = page.items
            total = page.total
            nextOffset = page.nextOffset
            loadMoreFailed = false
            loadedFilterKey = filterKey
            if !page.categories.isEmpty { categories = page.categories }
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                isLoading = false
                return
            }
            errorMessage = error.kaixUserMessage
            isLoading = false
        }
    }

    /// 从详情页返回时的静默刷新:仅用第一页更新已有条目状态(报名数/viewer 状态等)、
    /// 把新出现的活动插到最前;不重置 items/nextOffset,保住分页进度与滚动位置。
    private func refreshSilently() async {
        let generation = loadGeneration
        guard let page = try? await KaiXAPIClient.shared.events(
            countryCode: RegionStore.shared.current?.countryCode ?? "jp",
            category: selectedCategory.isEmpty ? nil : selectedCategory,
            when: when
        ) else { return }
        guard generation == loadGeneration else { return }
        total = page.total
        if !page.categories.isEmpty { categories = page.categories }
        let refreshed = Dictionary(page.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existing = Set(items.map(\.id))
        items = page.items.filter { !existing.contains($0.id) } + items.map { refreshed[$0.id] ?? $0 }
    }

    private func loadMore() async {
        guard !isLoadingMore, let offset = nextOffset else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = loadGeneration
        do {
            let page = try await KaiXAPIClient.shared.events(
                countryCode: RegionStore.shared.current?.countryCode ?? "jp",
                category: selectedCategory.isEmpty ? nil : selectedCategory,
                when: when,
                offset: offset
            )
            guard generation == loadGeneration else { return }
            let existing = Set(items.map(\.id))
            items += page.items.filter { !existing.contains($0.id) }
            nextOffset = page.nextOffset
            loadMoreFailed = false
        } catch {
            guard generation == loadGeneration else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            // 一次瞬时失败不能置 nextOffset=nil 永久终结分页(用户会以为「就这么多」),
            // 保留 offset、亮出内联重试。
            loadMoreFailed = true
        }
    }
}

// MARK: - 活动卡(Luma 式:大图 + 日期块 + 信息层)

private struct EventCard: View {
    let event: KaiXEventDTO
    let language: AppLanguage
    let onOpen: () -> Void

    private var tint: Color { KXEventStyle.tint(event.category ?? "party") }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                cover
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    HStack(spacing: 6) {
                        Label(KXEventStyle.label(event.category ?? "party", fallback: event.category_label, language), systemImage: KXEventStyle.icon(event.category ?? "party"))
                            .font(.caption2.weight(.black))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .frame(height: 21)
                            .background(tint.opacity(0.12), in: Capsule())
                        if event.is_featured ?? false {
                            Label(KXListingCopy.pickText(language, "精选", "注目", "Featured"), systemImage: "star.fill")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(KXColor.rankGold)
                                .padding(.horizontal, 8)
                                .frame(height: 21)
                                .background(KXColor.rankGold.opacity(0.13), in: Capsule())
                        }
                        Spacer(minLength: 0)
                        if let price = event.price_text, !price.isEmpty {
                            Text(price)
                                .font(.caption.weight(.black))
                                .foregroundStyle(KXColor.livingWarm)
                        }
                    }
                    Text(event.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Label(KXEventStyle.timeLine(event.starts_at, event.ends_at, timezone: event.timezone, language: language), systemImage: "clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let venue = event.venue_name, !venue.isEmpty {
                            Label(venue, systemImage: "mappin.and.ellipse")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    HStack(spacing: KXSpacing.sm) {
                        KXAvatarStack(users: event.attendees_preview ?? [], totalCount: event.goingCountValue, size: 24)
                        if event.goingCountValue > 0 {
                            Text(KXListingCopy.pickText(language, "\(event.goingCountValue) 人参加", "\(event.goingCountValue)人参加", "\(event.goingCountValue) going"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(KXListingCopy.pickText(language, "等你来报名", "参加者募集中", "Be the first to join"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        if event.viewerGoing {
                            Label(KXListingCopy.pickText(language, "已报名", "参加予定", "Going"), systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KXColor.accent)
                        }
                    }
                }
                .padding(14)
            }
            .kxGlassSurface(radius: KXRadius.lg)
            .clipShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
        }
        .buttonStyle(KXPressableStyle(scale: 0.98))
    }

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let raw = event.cover_url, let url = raw.kaixMediaURL {
                    CachedMediaImageView(url: url, targetPixelSize: 1200)
                } else {
                    LinearGradient(
                        colors: [tint.opacity(0.85), tint.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: KXEventStyle.icon(event.category ?? "party"))
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(KXColor.onTint(tint).opacity(0.85))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()

            if let badge = KXEventStyle.dateBadge(event.starts_at, timezone: event.timezone, language: language) {
                VStack(spacing: 0) {
                    Text(badge.month)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(KXColor.heat)
                    Text(badge.day)
                        .font(.title3.weight(.black))
                        .foregroundStyle(.primary)
                }
                .frame(width: 48, height: 50)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .padding(10)
            }
        }
    }
}
