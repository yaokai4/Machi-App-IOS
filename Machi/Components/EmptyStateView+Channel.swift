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
        let pick: (String, String, String) -> String = { zh, ja, en in
            switch language {
            case .ja: return ja
            case .en: return en
            default: return zh
            }
        }
        switch channel {
        case .secondhand:
            return .init(icon: "tag", title: pick("这里还没有二手内容", "まだフリマ投稿がありません", "No marketplace posts yet"), body: pick("发布第一个闲置吧。其他人会看到你的物品。", "最初の出品をすると、近くの人に届きます。", "List the first item so people nearby can find it."), cta: pick("发布二手", "出品する", "List item"), tint: .green)
        case .housing:
            return .init(icon: "house", title: pick("还没有租房信息", "まだ賃貸情報がありません", "No rental posts yet"), body: pick("发布转租、合租或找室友,帮新到的人找到家。", "転貸、ルームシェア、同居人募集を投稿して、新しく来た人を助けましょう。", "Post sublets, roomshares, or roommate leads to help newcomers settle in."), cta: pick("发布租房", "物件を投稿", "Post rental"), tint: .blue)
        case .jobPost:
            return .init(icon: "briefcase", title: pick("还没有招聘信息", "まだ求人情報がありません", "No hiring posts yet"), body: pick("发布本地招聘,把岗位推送给同城求职者。", "地域の求人を投稿して、同じ街の求職者に届けましょう。", "Post a local role and reach candidates in this city."), cta: pick("发布招聘", "求人を投稿", "Post job"), tint: KXColor.rankViolet)
        case .jobSeek:
            return .init(icon: "person.crop.rectangle", title: pick("还没有求职帖", "まだ求職投稿がありません", "No job-seeking posts yet"), body: pick("把你的求职方向告诉同城的人,招聘方会看到。", "希望職種や働ける時間を投稿すると、採用側に届きます。", "Share what kind of work you want so hiring teams can find you."), cta: pick("发布求职", "求職を投稿", "Post profile"), tint: .mint)
        case .meetup:
            return .init(icon: "person.2", title: pick("还没有小组内容", "まだグループ投稿がありません", "No group posts yet"), body: pick("发起一个学习、运动或语言交换讨论,让本地社区参与进来。", "勉強、スポーツ、言語交換などを始めて、地域の人とつながりましょう。", "Start a study, sports, or language-exchange thread for the local community."), cta: pick("发布小组", "グループ投稿", "Post group"), tint: .orange)
        case .dining:
            return .init(icon: "fork.knife", title: pick("还没有美食讨论", "まだグルメ投稿がありません", "No dining posts yet"), body: pick("发布餐厅、咖啡或本地美食活动讨论。", "レストラン、カフェ、地域のグルメイベントを投稿しましょう。", "Share restaurants, cafes, or local dining events."), cta: pick("发布美食", "グルメ投稿", "Post dining"), tint: KXColor.rankCoral)
        case .event:
            return .init(icon: "calendar", title: pick("还没有活动", "まだイベントがありません", "No events yet"), body: pick("发布本地活动,把线下聚会同步给社群。", "地域イベントを投稿して、オフラインの集まりを共有しましょう。", "Post a local event so the community can join offline."), cta: pick("发布活动", "イベント投稿", "Post event"), tint: .purple)
        case .guide:
            return .init(icon: "book", title: pick("这里还没有攻略", "まだガイド投稿がありません", "No guides yet"), body: pick("分享你的本地生活经验,帮助后来的人少走弯路。", "地域での経験を共有して、次に来る人を助けましょう。", "Share local know-how so the next person has an easier start."), cta: pick("写攻略", "ガイドを書く", "Write guide"), tint: KXColor.rankTeal)
        case .news, .recommend, .hot:
            return .init(icon: "newspaper", title: pick("还没有本地资讯", "まだ地域ニュースがありません", "No local updates yet"), body: pick("发布一条本地快讯,把信息同步给社群。", "地域の速報やお知らせを投稿して共有しましょう。", "Post a local update and share it with the community."), cta: pick("发布资讯", "情報を投稿", "Post update"), tint: KXColor.rankSky)
        case .question:
            return .init(icon: "questionmark.bubble", title: pick("还没有问答", "まだ質問がありません", "No questions yet"), body: pick("提出你的生活疑问,本地人会来回答。", "暮らしの疑問を投稿すると、地元の人が答えてくれます。", "Ask a local-life question and people nearby can help."), cta: pick("提个问", "質問する", "Ask"), tint: .indigo)
        case .service:
            return .init(icon: "wrench.and.screwdriver", title: pick("还没有服务", "まだ地域サービスがありません", "No local services yet"), body: pick("发布餐饮预约、接送交通、翻译手续、搬家清洁或生活开通等服务。", "飲食予約、送迎、翻訳・手続き、引越し清掃、生活手続きを投稿できます。", "Post dining bookings, transfers, paperwork help, moving, cleaning, or life setup services."), cta: pick("发布服务", "サービスを投稿", "Post service"), tint: .brown)
        case .merchant:
            return .init(icon: "storefront", title: pick("还没有商家", "まだ店舗がありません", "No businesses yet"), body: pick("把你的店推介给同城人,从认证开始。", "店舗を同じ街の人に紹介しましょう。まずは認証から始められます。", "Introduce your business to people in the city, starting with verification."), cta: pick("认证商家", "店舗を認証", "Verify business"), tint: .teal)
        case .coupon:
            return .init(icon: "ticket", title: pick("还没有优惠", "まだ特典がありません", "No deals yet"), body: pick("发布折扣或活动,让更多人到店。", "割引やキャンペーンを投稿して来店につなげましょう。", "Post a deal or campaign to bring more people in."), cta: pick("发布优惠", "特典を投稿", "Post deal"), tint: KXColor.heat)
        case .warning:
            return .init(icon: "exclamationmark.shield", title: pick("还没有避坑信息", "まだ注意喚起がありません", "No safety notes yet"), body: pick("把你踩过的坑告诉大家,大家都能少走弯路。", "困った経験を共有して、ほかの人が避けられるようにしましょう。", "Share what went wrong so others can avoid it."), cta: pick("写避坑", "注意を書く", "Post warning"), tint: .red)
        case .dynamic:
            return .init(icon: "text.bubble", title: pick("这里还没有动态", "まだ投稿がありません", "No posts yet"), body: pick("和大家聊聊近况,看看本地正在发生什么。", "近況を投稿して、この街で起きていることを共有しましょう。", "Share what is happening around you and start the local conversation."), cta: pick("发动态", "投稿する", "Post"), tint: .blue)
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
