import SwiftUI

/// A richer empty-state used by every channel feed (secondhand,
/// housing, jobs, meetup, …). Includes channel-specific copy and a
/// primary "post in this channel" CTA so the user is never told
/// "no content" without a way to fix it.
///
/// Built as a separate component (not a factory on `EmptyStateView`)
/// because it embeds an action button and the original is purely
/// presentational. Use `EmptyStateView` for read-only states (a
/// generic "tray" graphic) and `ChannelEmptyState` whenever the user
/// can resolve the emptiness by posting.
struct ChannelEmptyState: View {
    @Environment(\.appLanguage) private var language
    let channel: CityChannel
    var onCompose: (() -> Void)?

    private struct Copy {
        let icon: String
        let title: String
        let body: String
        let cta: String
        let tint: Color
    }

    private var copy: Copy {
        switch channel {
        case .secondhand:
            return .init(icon: "tag", title: "这里还没有二手内容", body: "发布第一个闲置吧。其他人会看到你的物品。", cta: "发布二手", tint: .green)
        case .housing:
            return .init(icon: "house", title: "还没有租房信息", body: "发布转租、合租或找室友,帮新到的人找到家。", cta: "发布租房", tint: .blue)
        case .jobPost:
            return .init(icon: "briefcase", title: "还没有招聘信息", body: "发布本地招聘,把岗位推送给同城求职者。", cta: "发布招聘", tint: KXColor.rankViolet)
        case .jobSeek:
            return .init(icon: "person.crop.rectangle", title: "还没有求职帖", body: "把你的求职方向告诉同城的人,招聘方会看到。", cta: "发布求职", tint: .mint)
        case .meetup:
            return .init(icon: "person.2", title: "还没有搭子内容", body: "发起一个饭局、学习局或运动局,认识同城的人。", cta: "发布搭子", tint: .orange)
        case .dining:
            return .init(icon: "fork.knife", title: "还没有约饭局", body: "约一顿饭、一杯咖啡,见见同城的朋友。", cta: "发布约饭", tint: KXColor.rankCoral)
        case .event:
            return .init(icon: "calendar", title: "还没有活动", body: "发布本地活动,把线下聚会同步给社群。", cta: "发布活动", tint: .purple)
        case .guide:
            return .init(icon: "book", title: "这里还没有攻略", body: "分享你的本地生活经验,帮助后来的人少走弯路。", cta: "写攻略", tint: KXColor.rankTeal)
        case .news, .recommend, .hot:
            return .init(icon: "newspaper", title: "还没有本地资讯", body: "发布一条本地快讯,把信息同步给社群。", cta: "发布资讯", tint: KXColor.rankSky)
        case .question:
            return .init(icon: "questionmark.bubble", title: "还没有问答", body: "提出你的生活疑问,本地人会来回答。", cta: "提个问", tint: .indigo)
        case .service:
            return .init(icon: "wrench.and.screwdriver", title: "还没有服务", body: "发布搬家、签证、辅导等本地服务。", cta: "发布服务", tint: .brown)
        case .merchant:
            return .init(icon: "storefront", title: "还没有商家", body: "把你的店推介给同城人,从认证开始。", cta: "认证商家", tint: .teal)
        case .coupon:
            return .init(icon: "ticket", title: "还没有优惠", body: "发布折扣或活动,让更多人到店。", cta: "发布优惠", tint: KXColor.heat)
        case .warning:
            return .init(icon: "exclamationmark.shield", title: "还没有避坑信息", body: "把你踩过的坑告诉大家,大家都能少走弯路。", cta: "写避坑", tint: .red)
        case .dynamic:
            return .init(icon: "text.bubble", title: "这里还没有动态", body: "和大家聊聊近况,看看本地正在发生什么。", cta: "发动态", tint: .blue)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: copy.icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(copy.tint)
                .frame(width: 64, height: 64)
                .background(copy.tint.opacity(0.12), in: Circle())

            Text(copy.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(copy.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let onCompose {
                Button(action: onCompose) {
                    Label(copy.cta, systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .background(copy.tint, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, KXSpacing.lg)
        .padding(.vertical, KXSpacing.xl)
        .frame(maxWidth: .infinity)
        .kxGlassSurface(radius: KXRadius.lg)
        .padding(.horizontal, KXSpacing.screen)
    }
}
