import SwiftUI

// MARK: - 活动样式速查

enum KXEventStyle {
    static func icon(_ key: String) -> String {
        switch key {
        case "drinks": "wineglass.fill"
        case "food": "fork.knife"
        case "art": "paintpalette.fill"
        case "reading": "book.fill"
        case "music": "music.note"
        case "outdoor": "leaf.fill"
        case "market": "bag.fill"
        case "talk": "mic.fill"
        case "sports": "sportscourt.fill"
        case "social": "person.3.fill"
        default: "sparkles"
        }
    }

    static func tint(_ key: String) -> Color {
        switch key {
        case "drinks": .pink
        case "food": .orange
        case "art": .purple
        case "reading": .teal
        case "music": .indigo
        case "outdoor": .green
        case "market": .brown
        case "talk": .blue
        case "sports": .mint
        case "social": .cyan
        default: .gray
        }
    }

    static func label(_ key: String, fallback: String?, _ language: AppLanguage) -> String {
        let table: [String: (zh: String, ja: String, en: String)] = [
            "drinks": ("酒局小聚", "飲み会", "Drinks"),
            "food": ("美食饭局", "グルメ", "Food"),
            "art": ("展览艺术", "アート", "Art"),
            "reading": ("读书会", "読書会", "Reading"),
            "music": ("音乐演出", "音楽", "Music"),
            "outdoor": ("户外徒步", "アウトドア", "Outdoor"),
            "market": ("市集", "マルシェ", "Market"),
            "talk": ("讲座分享", "トーク", "Talks"),
            "sports": ("运动", "スポーツ", "Sports"),
            "social": ("交友社群", "交流会", "Social"),
            "other": ("其他", "その他", "Other"),
        ]
        if let entry = table[key] {
            return KXListingCopy.pickText(language, entry.zh, entry.ja, entry.en)
        }
        return fallback ?? key
    }

    /// Luma 式日期块:「7月」+「12」两行。
    static func dateBadge(_ raw: String?, language: AppLanguage) -> (month: String, day: String)? {
        guard let raw, let date = KXDateParsing.parse(raw) else { return nil }
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: language == .ja ? "ja_JP" : (language == .en ? "en_US" : "zh_CN"))
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d"
        return (monthFormatter.string(from: date), dayFormatter.string(from: date))
    }

    static func timeLine(_ startRaw: String?, _ endRaw: String?, language: AppLanguage) -> String {
        guard let startRaw, let start = KXDateParsing.parse(startRaw) else { return startRaw ?? "" }
        let locale = Locale(identifier: language == .ja ? "ja_JP" : (language == .en ? "en_US" : "zh_CN"))
        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateFormat = "HH:mm"
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

    var body: some View {
        VStack(spacing: 0) {
            header
            filterRail
            ScrollView {
                LazyVStack(spacing: KXSpacing.lg) {
                    stateContent
                    if !isLoading, errorMessage == nil, nextOffset != nil {
                        KXInlineLoader()
                            .task(id: "\(items.count)|\(nextOffset ?? -1)") { await loadMore() }
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
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
                .padding(.trailing, KaiXTheme.horizontalPadding)
                .padding(.bottom, chrome.bottomContentPadding + 18)
        }
        .task(id: "\(selectedCategory)|\(when)") { await load() }
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
        .padding(.horizontal, KaiXTheme.horizontalPadding)
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
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.vertical, 9)
        }
    }

    private var displayCategories: [KaiXEventCategoryDTO] {
        if !categories.isEmpty { return categories }
        return ["drinks", "food", "art", "reading", "music", "outdoor", "market", "talk", "sports", "social"].map {
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
            .foregroundStyle(isSelected ? Color.white : tint)
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
                        .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
        } catch {
            guard generation == loadGeneration else { return }
            nextOffset = nil
        }
    }
}

// MARK: - 活动卡(Luma 式:大图 + 日期块 + 信息层)

private struct EventCard: View {
    let event: KaiXEventDTO
    let language: AppLanguage
    let onOpen: () -> Void

    private var tint: Color { KXEventStyle.tint(event.category ?? "social") }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                cover
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    HStack(spacing: 6) {
                        Label(KXEventStyle.label(event.category ?? "social", fallback: event.category_label, language), systemImage: KXEventStyle.icon(event.category ?? "social"))
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
                        Label(KXEventStyle.timeLine(event.starts_at, event.ends_at, language: language), systemImage: "clock")
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
                        Image(systemName: KXEventStyle.icon(event.category ?? "social"))
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()

            if let badge = KXEventStyle.dateBadge(event.starts_at, language: language) {
                VStack(spacing: 0) {
                    Text(badge.month)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(KXColor.heat)
                    Text(badge.day)
                        .font(.title3.weight(.black))
                        .foregroundStyle(.primary)
                }
                .frame(width: 48, height: 50)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(10)
            }
        }
    }
}
