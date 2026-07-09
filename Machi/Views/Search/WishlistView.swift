import Combine
import SwiftUI

/// A favorited listing snapshot cached locally (UserDefaults) so the user gets
/// an instant, offline 收藏 page. The server is the source of truth: heart
/// toggles POST/DELETE /api/listings/:id/favorite (see the card heart buttons),
/// and `syncFromServer()` reconciles from GET /api/my/favorites, so favorites
/// sync cross-device and cross-platform. This local store is an optimistic cache.
struct FavoriteSnapshot: Codable, Identifiable, Hashable {
    let id: String            // listingId
    var title: String
    /// 创建快照时语言下的价格标签——仅作老持久化数据的回退展示。
    var priceLabel: String
    var coverURLString: String?
    var type: String
    var locationText: String?
    var savedAt: Date
    // 原始价格数据(v2):收藏页渲染时用当前语言现算,不再把中文标签持久化
    // 后混进日/英界面。全部可选 → 老数据缺字段时解码为 nil,回退 priceLabel。
    var price: Double? = nil
    var currency: String? = nil
    var priceType: String? = nil
    var listingMode: String? = nil
    var hasPriceData: Bool? = nil

    var coverURL: URL? { coverURLString.flatMap { URL(string: $0) } }
}

@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    private let key = "kx.favorites.v1"
    @Published private(set) var items: [FavoriteSnapshot] = []
    /// 本会话内被用户明确取消收藏的 id。列表 DTO 里过期的 favorited=true 不该
    /// 再点亮红心——卡片以 store 为准,DTO 只作兜底(见各卡片的 favorited 推导)。
    /// 会话级即可:重启后服务端 DTO 已反映删除。
    @Published private(set) var removedIds: Set<String> = []
    @Published private(set) var isSyncing = false

    private init() { load() }

    func contains(_ id: String) -> Bool { items.contains { $0.id == id } }

    func wasRemoved(_ id: String) -> Bool { removedIds.contains(id) }

    /// Toggle a listing in/out of the local wishlist. Newest first.
    func set(_ snapshot: FavoriteSnapshot, on: Bool) {
        if on {
            removedIds.remove(snapshot.id)
            guard !contains(snapshot.id) else { return }
            items.insert(snapshot, at: 0)
        } else {
            removedIds.insert(snapshot.id)
            items.removeAll { $0.id == snapshot.id }
        }
        persist()
    }

    func remove(_ id: String) {
        removedIds.insert(id)
        items.removeAll { $0.id == id }
        persist()
    }

    static func snapshot(from listing: KaiXCityListingDTO) -> FavoriteSnapshot {
        FavoriteSnapshot(
            id: listing.id,
            title: KXListingCopy.displayTitle(listing),
            priceLabel: KXListingCopy.priceLabel(listing),
            coverURLString: listing.realCoverURL?.absoluteString,
            type: listing.type,
            locationText: listing.location_text,
            savedAt: Date(),
            price: listing.price,
            currency: listing.currency,
            priceType: listing.price_type ?? listing.priceType,
            listingMode: listing.attributes?["listing_mode"]?.listingDisplayValue,
            hasPriceData: true
        )
    }

    /// Pull the signed-in user's server-side favorites (GET /api/my/favorites,
    /// per type) and make them the source of truth — this is the cross-device
    /// sync. Aborts WITHOUT touching local state if any call fails (guest /
    /// offline), so a 401 never wipes the local list.
    func syncFromServer() async {
        // for_sale(买房)与其余频道同样可收藏(KXStayListingCard .forsale 变体
        // 和详情页都有心形)——漏在这张表里会被下面的整体替换把收藏静默清掉。
        let types = ["secondhand", "rental", "for_sale", "job", "hiring", "local_service", "discount"]
        isSyncing = true
        defer { isSyncing = false }
        var collected: [FavoriteSnapshot] = []
        var seen = Set<String>()
        for type in types {
            do {
                let listings = try await KaiXAPIClient.shared.savedListings(type: type)
                for listing in listings where !seen.contains(listing.id) {
                    seen.insert(listing.id)
                    collected.append(Self.snapshot(from: listing))
                }
            } catch {
                return
            }
        }
        // 服务端按 type 逐个拉取——上面未覆盖的类型(未来新增的可收藏类型)
        // 保留本地 snapshot,整体替换不能连它们的缓存一起删掉。
        let covered = Set(types)
        let preserved = items.filter { !covered.contains($0.type) && !seen.contains($0.id) }
        items = collected + preserved
        // 服务端此刻的收藏就是真相,本会话的「已取消」标记完成使命。
        removedIds = []
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FavoriteSnapshot].self, from: data) else { return }
        items = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Local 收藏 page, presented as a sheet from a channel header. Tapping a row
/// hands the listing id back to the host to push the detail (so navigation
/// happens on the host's stack after the sheet dismisses).
struct WishlistView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = FavoritesStore.shared
    /// When true (embedded in FavoritesHubView), render ONLY the list — no own
    /// NavigationStack / title / close — so the host's single close button isn't
    /// duplicated (the "two close buttons" bug).
    var embedded: Bool = false
    let onOpen: (String) -> Void
    /// Brief failure notice when a server-side unfavorite fails (row restored).
    @State private var removalNotice: String?

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle(KXListingCopy.pickText(language, "我的收藏", "お気に入り", "Saved"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel(L("close", language))
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        Group {
                if store.items.isEmpty {
                    if store.isSyncing {
                        KXSpinner()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyStateView(
                            title: KXListingCopy.pickText(language, "还没有收藏", "お気に入りはまだありません", "Nothing saved yet"),
                            subtitle: KXListingCopy.pickText(language, "在房源、商家或商品上点 ❤ 即可收藏，方便随时回看。", "物件・店舗・商品の ❤ で保存できます。", "Tap ❤ on any listing to save it here."),
                            systemImage: "heart",
                            illustration: .saved
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: KXSpacing.md) {
                            ForEach(store.items) { item in
                                WishlistRow(
                                    item: item,
                                    onOpen: { onOpen(item.id) },
                                    onRemove: { remove(item) }
                                )
                            }
                        }
                        .padding(.horizontal, KXSpacing.screen)
                        .padding(.vertical, 14)
                    }
                }
            }
            .background(KXColor.pageBackground.ignoresSafeArea())
            .overlay(alignment: .top) {
                if let removalNotice {
                    KXInlineNotice(message: removalNotice) {
                        self.removalNotice = nil
                    }
                    .padding(.horizontal, KXSpacing.screen)
                    .padding(.top, KXSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .task { await store.syncFromServer() }
    }

    /// Optimistically drop the row, then unfavorite on the server — the same
    /// write path as the card hearts (POST/DELETE /api/listings/:id/favorite)
    /// so the next `syncFromServer()` no longer resurrects the item. On
    /// failure the row is restored and a brief notice explains why.
    private func remove(_ item: FavoriteSnapshot) {
        withAnimation(.snappy(duration: 0.22)) { store.remove(item.id) }
        // Guests / signed-out sessions only have the local cache — nothing to
        // delete server-side (and the call would just 401).
        guard KaiXBackend.token != nil else { return }
        Task {
            do {
                try await KaiXAPIClient.shared.favoriteListing(item.id, on: false)
            } catch {
                withAnimation(.snappy(duration: 0.22)) { store.set(item, on: true) }
                removalNotice = KXListingCopy.pickText(
                    language,
                    "取消收藏失败，请重试",
                    "お気に入りを解除できませんでした。もう一度お試しください",
                    "Couldn't remove from saved — please try again"
                )
            }
        }
    }
}

private struct WishlistRow: View {
    @Environment(\.appLanguage) private var language
    let item: FavoriteSnapshot
    let onOpen: () -> Void
    let onRemove: () -> Void

    /// 有原始价格数据的快照用当前语言现算(切语言即时生效);老快照回退
    /// 持久化时的标签——否则日/英用户的收藏页会整行混入中文价签。
    private var priceText: String {
        if item.hasPriceData == true {
            return KXListingCopy.formatPrice(
                price: item.price,
                currency: item.currency,
                priceType: item.priceType,
                type: item.type,
                listingMode: item.listingMode,
                language
            )
        }
        return item.priceLabel
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: KXSpacing.md) {
                cover
                    .frame(width: 86, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(priceText)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(KXColor.livingWarm)
                        .lineLimit(1)
                    Text(item.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let loc = item.locationText, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Button(action: onRemove) {
                    Image(systemName: "heart.fill")
                        .font(.subheadline)
                        .foregroundStyle(KXColor.heat)
                        .frame(width: 34, height: 34)
                        .background(KXColor.livingSoft, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("delete", language))
            }
            .padding(10)
            .kxLivingSurface(radius: KXRadius.card, elevated: true)
        }
        .buttonStyle(KXPressableStyle())
    }

    @ViewBuilder
    private var cover: some View {
        if let url = item.coverURL {
            CachedMediaImageView(url: url, targetPixelSize: 260, failureMode: .transparent)
        } else {
            ZStack {
                KXColor.livingSoft
                Image(systemName: KXListingCopy.icon(for: item.type))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
    }
}
