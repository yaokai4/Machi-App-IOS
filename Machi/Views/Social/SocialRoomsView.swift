import SwiftUI

// MARK: - 房间样式速查

/// 约局 = 搭子 / 即兴组队。每种搭子一个「性格」:图标 + 主色,列表和详情共用。
/// 分类按「一起做什么」,与活动(按活动形式)彻底区分。含旧数据别名兼容。
enum KXRoomStyle {
    /// 旧 key(0708 首发)→新 key,与后端 _ROOM_TYPE_ALIASES 对齐。
    static func canonical(_ raw: String) -> String {
        switch raw {
        case "dining": "meal"
        case "drinks": "drink"
        case "boardgame", "karaoke": "play"
        case "sports": "sport"
        case "hangout": "chat"
        default: raw
        }
    }

    /// 现役分类顺序(供筛选/选择器)。
    static let orderedKeys = ["meal", "drink", "coffee", "sport", "study", "play", "carpool", "outing", "language", "chat"]

    static func icon(_ typeKey: String) -> String {
        switch canonical(typeKey) {
        case "meal": "fork.knife"
        case "drink": "wineglass.fill"
        case "coffee": "cup.and.saucer.fill"
        case "sport": "figure.run"
        case "study": "book.fill"
        case "play": "gamecontroller.fill"
        case "carpool": "car.fill"
        case "outing": "figure.walk"
        case "language": "bubble.left.and.bubble.right.fill"
        case "chat": "message.fill"
        default: "sparkles"
        }
    }

    /// 显式表取 KXColor trait-aware 语义色(rank 系 + chart 扩展色):同类目
    /// 色彩稳定、暗色模式提亮一档仍可读;原先的原生 .orange/.pink… 彩虹在
    /// 暗色下不成体系且与全局调色板脱节。
    static func tint(_ typeKey: String) -> Color {
        switch canonical(typeKey) {
        case "meal": KXColor.rankGold
        case "drink": KXColor.chartPink
        case "coffee": KXColor.livingWarm
        case "sport": KXColor.chartGreen
        case "study": KXColor.rankTeal
        case "play": KXColor.rankViolet
        case "carpool": KXColor.chartSlate
        case "outing": KXColor.rankSky
        case "language": KXColor.rankCoral
        case "chat": KXColor.categoryNeutral
        default: KXColor.categoryNeutral
        }
    }

    static func label(_ typeKey: String, fallback: String?, _ language: AppLanguage) -> String {
        let table: [String: (zh: String, ja: String, en: String)] = [
            "meal": ("饭搭子", "ごはん友達", "Meal buddy"),
            "drink": ("酒搭子", "飲み友達", "Drink buddy"),
            "coffee": ("咖啡", "カフェ", "Coffee"),
            "sport": ("运动搭子", "運動仲間", "Workout buddy"),
            "study": ("学习搭子", "勉強仲間", "Study buddy"),
            "play": ("玩乐", "遊び", "Play"),
            "carpool": ("拼车拼单", "相乗り・共同購入", "Carpool"),
            "outing": ("出行搭子", "おでかけ", "Outing"),
            "language": ("语言交换", "言語交換", "Language"),
            "chat": ("随便聊", "雑談", "Just chat"),
            "other": ("其他", "その他", "Other"),
        ]
        if let entry = table[canonical(typeKey)] {
            return KXListingCopy.pickText(language, entry.zh, entry.ja, entry.en)
        }
        return fallback ?? typeKey
    }
}

/// DTO 版头像(房间成员/活动参与者不是本地 UserEntity)。带首字母兜底。
struct KXSocialAvatar: View {
    let user: KaiXUserDTO?
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.kaixNamed(user?.avatar_color ?? "indigo").gradient)
            Text(initial)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let raw = user?.avatar_url ?? user?.avatarUrl, let url = raw.kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: size * 3, failureMode: .transparent)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: String {
        let name = (user?.displayName ?? user?.display_name ?? "").trimmingCharacters(in: .whitespaces)
        guard let first = name.first else { return "?" }
        return String(first).uppercased()
    }
}

/// 叠起来的成员头像 + 「+N」——房间卡上的「里面有谁」。
struct KXAvatarStack: View {
    let users: [KaiXUserDTO]
    let totalCount: Int
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(Array(users.prefix(5).enumerated()), id: \.element.id) { _, user in
                KXSocialAvatar(user: user, size: size)
                    .overlay(Circle().stroke(KXColor.cardBackground, lineWidth: 1.6))
            }
            if totalCount > min(users.count, 5) {
                Text("+\(totalCount - min(users.count, 5))")
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(KXColor.softBackground, in: Circle())
                    .overlay(Circle().stroke(KXColor.cardBackground, lineWidth: 1.6))
            }
        }
    }
}

// MARK: - 房间广场

/// 交友 · 约局 · 约饭 —— 像游戏大厅一样的房间列表:每个局是一张房间卡,
/// 看得到里面的人、标题、时间和还差几个人;点进去就是房间(成员 + 聊天)。
struct SocialRoomsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState

    let currentUser: UserEntity

    @State private var items: [KaiXRoomDTO] = []
    @State private var roomTypes: [KaiXRoomTypeDTO] = []
    @State private var total = 0
    @State private var nextOffset: Int?
    @State private var selectedType = ""
    @State private var onlyMine = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var createOpen = false
    @State private var loadGeneration = 0
    /// loadMore 瞬时失败标记:保留 nextOffset 给内联重试,而不是静默终结分页。
    @State private var loadMoreFailed = false
    /// 已成功整表加载过的筛选组合;pop 回来 task 重启时据此走静默刷新而非整表重置。
    @State private var loadedFilterKey: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            typeRail
            ScrollView {
                LazyVStack(spacing: KXSpacing.md) {
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
        .sheet(isPresented: $createOpen) {
            CreateRoomSheet(currentUser: currentUser) { room in
                items.insert(room, at: 0)
                total += 1
                router.open(.socialRoom(roomId: room.id))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXRoomRemoved)) { note in
            // 解散的房间无条件剔除(再点会 404);成员退出的房间仅在「我的局」筛选下
            // 剔除(它不再属于我加入的局),广场筛选下留给 refreshSilently 更新为未加入。
            guard let id = note.userInfo?["id"] as? String else { return }
            let disbanded = (note.userInfo?["disbanded"] as? Bool) ?? true
            if disbanded || onlyMine {
                items.removeAll { $0.id == id }
                total = max(0, total - 1)
            }
        }
        .task(id: "\(selectedType)|\(onlyMine)") {
            // NavigationStack 里 push 房间再 pop 回来,.task 会以相同 id 重启:
            // 此时只做静默合并刷新,保留 loadMore 累积的分页与滚动位置;
            // 只有筛选真正变化(或首载/上次失败)才整表重载。
            if loadedFilterKey == "\(selectedType)|\(onlyMine)", !items.isEmpty {
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
                Text(KXListingCopy.pickText(language, "交友 · 约局 · 约饭", "友達 · 遊び · ごはん", "Meet & Hang out"))
                    .font(.headline.weight(.bold))
                Text(KXListingCopy.pickText(language, "\(total) 个进行中的局", "\(total)件のルーム", "\(total) open rooms"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onlyMine.toggle()
            } label: {
                Text(KXListingCopy.pickText(language, "我的局", "参加中", "Mine"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(onlyMine ? KXColor.onAccent : .primary)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(onlyMine ? KXColor.accent : KXColor.softBackground.opacity(0.9), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.sm)
        .kxGlassBar(ignoresTopSafeArea: true)
    }

    private var typeRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KXSpacing.sm) {
                typeChip(key: "", label: KXListingCopy.pickText(language, "全部", "すべて", "All"), icon: "square.grid.2x2")
                ForEach(displayTypes) { type in
                    typeChip(key: type.key, label: KXRoomStyle.label(type.key, fallback: type.label, language), icon: KXRoomStyle.icon(type.key))
                }
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.vertical, 9)
        }
    }

    /// 服务端给的现役类型;首载前用本地兜底,让筛选行第一帧就有内容。
    private var displayTypes: [KaiXRoomTypeDTO] {
        if !roomTypes.isEmpty { return roomTypes }
        return KXRoomStyle.orderedKeys.map {
            KaiXRoomTypeDTO(key: $0, label: $0)
        }
    }

    private func typeChip(key: String, label: String, icon: String) -> some View {
        let isSelected = selectedType == key
        let tint = key.isEmpty ? KXColor.accent : KXRoomStyle.tint(key)
        return Button {
            selectedType = key
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
            VStack(spacing: KXSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in KXBigPhotoSkeletonCard() }
            }
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) { Task { await load() } }
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if items.isEmpty {
            VStack(spacing: 18) {
                EmptyStateView(
                    title: onlyMine
                        ? KXListingCopy.pickText(language, "你还没有加入任何局", "参加中のルームはありません", "You haven't joined any rooms")
                        : KXListingCopy.pickText(language, "还没有进行中的局", "まだルームがありません", "No open rooms yet"),
                    subtitle: KXListingCopy.pickText(language, "开一个局,喊大家一起吃饭、喝酒、打桌游", "ルームを作って、ごはんや飲み会に誘ってみましょう", "Start a room and invite people to eat, drink or play"),
                    systemImage: "person.3"
                )
                Button {
                    openCreate()
                } label: {
                    Label(KXListingCopy.pickText(language, "开个局", "ルームを作る", "Start a room"), systemImage: "plus.circle.fill")
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
            ForEach(items) { room in
                SocialRoomCard(room: room, language: language) {
                    router.open(.socialRoom(roomId: room.id))
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
        .accessibilityLabel(KXListingCopy.pickText(language, "开个局", "ルームを作る", "Start a room"))
    }

    private func openCreate() {
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以开局。", "ログインするとルームを作れます。", "Sign in to start a room.")) else { return }
        createOpen = true
    }

    private func load() async {
        isLoading = items.isEmpty
        loadGeneration += 1
        let generation = loadGeneration
        let filterKey = "\(selectedType)|\(onlyMine)"
        errorMessage = nil
        do {
            // 默认全国:局本来就少,先让人看到人气;想只看本地用类型/城市筛。
            let page = try await KaiXAPIClient.shared.rooms(
                countryCode: RegionStore.shared.current?.countryCode ?? "jp",
                type: selectedType.isEmpty ? nil : selectedType,
                mine: onlyMine
            )
            guard generation == loadGeneration else { return }
            items = page.items
            total = page.total
            nextOffset = page.nextOffset
            loadMoreFailed = false
            loadedFilterKey = filterKey
            if !page.roomTypes.isEmpty { roomTypes = page.roomTypes }
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

    /// 从房间详情返回时的静默刷新:仅用第一页更新已有卡片状态(人数/已加入等)、
    /// 把新出现的局插到最前;不重置 items/nextOffset,保住分页进度与滚动位置。
    private func refreshSilently() async {
        let generation = loadGeneration
        guard let page = try? await KaiXAPIClient.shared.rooms(
            countryCode: RegionStore.shared.current?.countryCode ?? "jp",
            type: selectedType.isEmpty ? nil : selectedType,
            mine: onlyMine
        ) else { return }
        guard generation == loadGeneration else { return }
        total = page.total
        if !page.roomTypes.isEmpty { roomTypes = page.roomTypes }
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
            let page = try await KaiXAPIClient.shared.rooms(
                countryCode: RegionStore.shared.current?.countryCode ?? "jp",
                type: selectedType.isEmpty ? nil : selectedType,
                mine: onlyMine,
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

// MARK: - 房间卡

private struct SocialRoomCard: View {
    let room: KaiXRoomDTO
    let language: AppLanguage
    let onOpen: () -> Void

    private var tint: Color { KXRoomStyle.tint(room.typeKey) }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(alignment: .top, spacing: KXSpacing.md) {
                    Image(systemName: KXRoomStyle.icon(room.typeKey))
                        .kxScaledFont(18, weight: .bold)
                        .foregroundStyle(KXColor.onTint(tint))
                        .frame(width: 44, height: 44)
                        .background(
                            LinearGradient(colors: [tint.opacity(0.92), tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(KXRoomStyle.label(room.typeKey, fallback: room.room_type_label, language))
                                .font(.caption2.weight(.black))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 7)
                                .frame(height: 19)
                                .background(tint.opacity(0.12), in: Capsule())
                            if room.joined {
                                Text(KXListingCopy.pickText(language, "已加入", "参加中", "Joined"))
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(KXColor.accent)
                                    .padding(.horizontal, 7)
                                    .frame(height: 19)
                                    .background(KXColor.accent.opacity(0.12), in: Capsule())
                            }
                            Spacer(minLength: 0)
                            capacityBadge
                        }
                        Text(room.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let description = room.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: KXSpacing.sm) {
                    KXAvatarStack(users: room.members ?? [], totalCount: room.memberCountValue)
                    Text(KXListingCopy.pickText(language, "\(room.memberCountValue) 人在房间里", "\(room.memberCountValue)人が参加中", "\(room.memberCountValue) inside"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let meta = metaLine {
                        Label(meta.text, systemImage: meta.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxGlassSurface(radius: KXRadius.lg)
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
        }
        .buttonStyle(KXPressableStyle(scale: 0.98))
    }

    @ViewBuilder
    private var capacityBadge: some View {
        if room.capacityValue > 0 {
            let full = room.memberCountValue >= room.capacityValue
            Text("\(room.memberCountValue)/\(room.capacityValue)")
                .font(.caption.weight(.black))
                .foregroundStyle(full ? KXColor.heat : .secondary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background((full ? KXColor.heat : Color.secondary).opacity(0.10), in: Capsule())
        }
    }

    private var metaLine: (icon: String, text: String)? {
        if let startsAt = room.starts_at, !startsAt.isEmpty {
            if let date = KXDateParsing.parse(startsAt) {
                // starts_at 是 UTC 瞬时,约局是日本本地线下聚会,固定 JST 渲染——
                // 与活动端一致,否则海外设备时区的用户看到错位墙钟(详见 SocialRoomDetailView.formattedTime)。
                // 列表滚动热路径:用缓存 formatter,别每卡每帧做 ICU 模板解析。
                let formatter = KXSocialDateFormatters.templated("MMMdEHHmm", language: language, timeZone: KXEventStyle.displayTimeZone(nil))
                return ("calendar", formatter.string(from: date))
            }
            return ("calendar", startsAt)
        }
        if let hint = room.location_hint, !hint.isEmpty {
            return ("mappin.and.ellipse", hint)
        }
        return nil
    }
}

// MARK: - 开局

private struct CreateRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    let currentUser: UserEntity
    let onCreated: (KaiXRoomDTO) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var roomType = "meal"
    @State private var locationHint = ""
    @State private var hasStartTime = false
    @State private var startsAt = Date().addingTimeInterval(3600 * 4)
    @State private var capacity = 4
    @State private var hasCapacity = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    typePicker
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel(KXListingCopy.pickText(language, "局的名字", "タイトル", "Room name"), required: true)
                        TextField(KXListingCopy.pickText(language, "例如 周五晚新宿吃烤肉,来仨人", "例:金曜夜、新宿で焼肉", "e.g. Friday yakiniku in Shinjuku"), text: $title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, KXSpacing.md)
                            .frame(height: 46)
                            .kxGlassSurface(radius: KXRadius.md)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel(KXListingCopy.pickText(language, "想说的话", "ひとこと", "Details"))
                        TextField(
                            KXListingCopy.pickText(language, "预算、口味、见面方式…随便写", "予算や集合方法など", "Budget, tastes, how to meet…"),
                            text: $description, axis: .vertical
                        )
                        .font(.subheadline)
                        .lineLimit(3...6)
                        .padding(KXSpacing.md)
                        .kxGlassSurface(radius: KXRadius.md)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel(KXListingCopy.pickText(language, "大概位置(可选)", "場所のヒント(任意)", "Location hint (optional)"))
                        TextField(KXListingCopy.pickText(language, "例如 新宿站东口 / 涩谷附近", "例:新宿駅東口あたり", "e.g. Shinjuku east exit"), text: $locationHint)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, KXSpacing.md)
                            .frame(height: 46)
                            .kxGlassSurface(radius: KXRadius.md)
                    }
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        Toggle(isOn: $hasStartTime.animation(.snappy(duration: 0.2))) {
                            fieldLabel(KXListingCopy.pickText(language, "约定时间", "日時を決める", "Set a time"))
                        }
                        .tint(KXColor.accent)
                        if hasStartTime {
                            DatePicker("", selection: $startsAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }
                    }
                    .padding(KXSpacing.md)
                    .kxGlassSurface(radius: KXRadius.md)
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        Toggle(isOn: $hasCapacity.animation(.snappy(duration: 0.2))) {
                            fieldLabel(KXListingCopy.pickText(language, "限制人数", "人数を決める", "Limit spots"))
                        }
                        .tint(KXColor.accent)
                        if hasCapacity {
                            Stepper(value: $capacity, in: 2...50) {
                                Text(KXListingCopy.pickText(language, "共 \(capacity) 人(含你)", "\(capacity)人まで(自分を含む)", "\(capacity) people (incl. you)"))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .padding(KXSpacing.md)
                    .kxGlassSurface(radius: KXRadius.md)
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
            .navigationTitle(KXListingCopy.pickText(language, "开个局", "ルームを作る", "Start a room"))
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
                            Text(KXListingCopy.pickText(language, "开局", "作成", "Create"))
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func fieldLabel(_ text: String, required: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            if required {
                Text("*").font(.caption.weight(.black)).foregroundStyle(KXColor.heat)
            }
        }
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            fieldLabel(KXListingCopy.pickText(language, "这是个什么局?", "どんなルーム?", "What kind of room?"), required: true)
            FlowLayout(spacing: KXSpacing.sm) {
                ForEach(KXRoomStyle.orderedKeys + ["other"], id: \.self) { key in
                    let isSelected = roomType == key
                    let tint = KXRoomStyle.tint(key)
                    Button {
                        roomType = key
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: KXRoomStyle.icon(key))
                                .font(.caption.weight(.bold))
                            Text(KXRoomStyle.label(key, fallback: nil, language))
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(isSelected ? KXColor.onTint(tint) : tint)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(isSelected ? tint : tint.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let region = RegionStore.shared.current
            let room = try await KaiXAPIClient.shared.createRoom(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                roomType: roomType,
                countryCode: region?.countryCode ?? "jp",
                citySlug: region?.cityCode ?? "",
                regionCode: region?.regionCode ?? "",
                locationHint: locationHint.trimmingCharacters(in: .whitespacesAndNewlines),
                startsAt: hasStartTime ? KXDateParsing.iso.string(from: startsAt) : "",
                capacity: hasCapacity ? capacity : 0
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSubmitting = false
            dismiss()
            onCreated(room)
        } catch {
            isSubmitting = false
            errorMessage = error.kaixUserMessage
        }
    }
}
