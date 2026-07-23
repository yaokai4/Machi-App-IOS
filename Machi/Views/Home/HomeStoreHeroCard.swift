import Combine
import SwiftUI

/// I2-1 首页 feed 的 hero SKU 曝光卡 — 全 App 最大流量面上给商城一个轻入口。
/// 复用 HomeJourneyNextStepCard 的「自加载、失败静默、不阻塞 feed」模式:
/// 拿不到商品就什么都不渲染,任何网络失败都不打扰 feed。取数与首页商城板块
/// (GuideStoreSection)同口径 —— is_featured + sort_order 置顶,兜底付费款。
/// 可关闭:关闭后本周期(7 天)不再出现,UserDefaults 记录截止时间。
@MainActor
final class HomeStoreHeroViewModel: ObservableObject {
    @Published private(set) var product: KaiXGuideProductDTO?
    /// 一次视图生命周期只上报一次曝光(load 会因语言切换等重入)。
    private var hasLoggedView = false

    func load() async {
        guard product == nil else { return }
        let resp = try? await KaiXAPIClient.shared.guideProducts(country: "jp", pageSize: 12)
        let items = (resp?.items ?? []).filter { !$0.isComingSoon && !$0.isService }
        let featured = items
            .filter { $0.isFeatured == true }
            .sorted { ($0.sortOrder ?? Int.max) < ($1.sortOrder ?? Int.max) }
        guard let hero = featured.first ?? items.first(where: { !$0.isFree }) ?? items.first else { return }
        // withAnimation + 视图 .transition 配对:数据晚到时卡片动画插入,
        // feed 不再被无动画地整列下顶。
        withAnimation(.snappy(duration: 0.3)) { product = hero }
        // C-2 客户端漏斗:卡片真的拿到 SKU 渲染出来才算一次曝光。
        if !hasLoggedView {
            hasLoggedView = true
            Task {
                await KaiXAPIClient.shared.funnelEvent(
                    "store_hero_view",
                    entityType: "guide_store",
                    entityId: hero.slug,
                    props: ["placement": "home_feed"]
                )
            }
        }
    }
}

struct HomeStoreHeroCard: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = HomeStoreHeroViewModel()
    /// 运营位互斥:旅程卡在场时本卡让位(首屏同屏最多一张运营卡,旅程卡
    /// 优先 —— 指路比开店门更贴用户当下)。由 HomeTimelineView 驱动。
    var isSuppressed: Bool = false
    /// 关闭后的静默截止时间(epoch 秒)。存截止时间而非布尔,让「本周期不再
    /// 出现」到期自动恢复,不需要清理逻辑。
    @AppStorage("home.storeHero.dismissedUntil") private var dismissedUntil: Double = 0

    /// 一个展示周期 = 7 天:关闭后本周期内不再出现。
    private static let dismissCycle: TimeInterval = 7 * 86_400

    private var isDismissed: Bool {
        Date().timeIntervalSince1970 < dismissedUntil
    }

    var body: some View {
        Group {
            if !isSuppressed, !isDismissed, let product = vm.product {
                Button {
                    router.open(.guideProduct(slug: product.slug), in: .home)
                } label: {
                    HStack(spacing: KXSpacing.md) {
                        Image(systemName: "bag.fill")
                            .kxScaledFont(15, weight: .bold)
                            .foregroundStyle(.orange)
                            .frame(width: 36, height: 36)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                            Text(KXListingCopy.pickText(language, "指南商城精选", "ガイドストアのおすすめ", "From the Guide store"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(product.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(GuideCopy.productPrice(product, language: language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                            .lineLimit(1)
                            .padding(.horizontal, KXSpacing.sm)
                            .frame(height: 22)
                            .background(KXColor.accentSoft, in: Capsule())
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(KXSpacing.md)
                    // 给右上角关闭钮留出空间,避免和价格胶囊/箭头重叠。
                    .padding(.trailing, KXSpacing.sm)
                    .contentShape(Rectangle())
                    .kxGlassSurface(radius: KXRadius.lg)
                }
                .buttonStyle(.fullArea)
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            dismissedUntil = Date().timeIntervalSince1970 + Self.dismissCycle
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .kxScaledFont(9, weight: .bold)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(KXListingCopy.pickText(language, "关闭推荐", "おすすめを閉じる", "Dismiss suggestion"))
                }
                // 与 vm.load 的 withAnimation 配对:插入/让位都有过渡。
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        // 以 isSuppressed 为 key:被旅程卡压住期间不取数(拿到也不渲染,
        // 还会虚报曝光漏斗);旅程卡消失(hint 变 nil)后再补载。
        .task(id: isSuppressed) {
            guard !isSuppressed, !isDismissed else { return }
            await vm.load()
        }
    }
}
