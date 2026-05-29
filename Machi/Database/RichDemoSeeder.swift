import Foundation
import SwiftData

/// Procedural demo-data generator. Produces ~100 users and ~300 posts
/// spread across regions / languages / content types so first-launch
/// users see a populated app even without a `KaiXBackend` server.
///
/// Identity:
/// - All users get a `rich-user-` prefix so `DatabaseSeeder.purgeDemoData`
///   can spot them on schema bumps.
/// - All posts get a `rich-post-` prefix similarly.
/// - Runs only when the existing user count is below `kickInThreshold`,
///   so an authoritative server feed can suppress it.
@MainActor
enum RichDemoSeeder {
    /// Below this number of *real* users we treat the local store as
    /// "empty" and inflate it with the demo dataset. Above this we
    /// assume the server feed is authoritative and skip seeding.
    static let kickInThreshold = 8

    /// Generate and insert the rich demo set. Caller is responsible for
    /// `try context.save()` afterwards — we batch everything into a
    /// single transaction so first-run cost stays small.
    static func seedIfNeeded(context: ModelContext) throws {
        let existingUsers = try context.fetch(FetchDescriptor<UserEntity>())
        // Already populated (real users from server / earlier rich seed)
        // — no-op so we don't keep stacking demo rows.
        guard existingUsers.count < kickInThreshold else { return }
        let alreadyRich = existingUsers.contains { $0.id.hasPrefix("rich-user-") }
        if alreadyRich { return }

        let users = makeUsers()
        users.forEach(context.insert)

        var generatedPosts: [PostEntity] = []
        for (index, user) in users.enumerated() {
            // Stable seed per user so reruns produce identical-looking
            // demo content; deterministic seeds also avoid surprising
            // diff churn in tests.
            let postCount = (index % 5) + 2
            for postIndex in 0..<postCount {
                let post = makePost(user: user, userIndex: index, postIndex: postIndex)
                context.insert(post)
                generatedPosts.append(post)
            }
        }

        // Cross-user follow graph — every 3rd user follows the next 2,
        // gives a few hubs without overwhelming the table.
        for (i, follower) in users.enumerated() {
            for offset in [1, 3, 7] where (i + offset) < users.count {
                let target = users[i + offset]
                context.insert(FollowEntity(
                    id: "rich-follow-\(i)-\(offset)",
                    followerId: follower.id,
                    followingId: target.id,
                    createdAt: .now.addingTimeInterval(Double(-i * 60))
                ))
                follower.followingCount += 1
                target.followerCount += 1
            }
        }
    }

    // MARK: - Users

    /// Source of names + bios + regions used to populate the demo
    /// users. Distributed across CN / JP / US / UK / CA / SG / KR /
    /// FR so the app's region filtering has interesting content
    /// everywhere a launch user might land.
    private struct UserSeed {
        let handle: String
        let displayName: String
        let bio: String
        let location: String
        let regionCode: String
        let language: String        // content language tag (zh / en / ja / ko / fr)
        let isMerchant: Bool
        let isVerified: Bool
        let role: UserRole
    }

    private static func makeUsers() -> [UserEntity] {
        let seeds = userSeeds
        return seeds.enumerated().map { index, seed in
            let region = KaiXRegionDirectory.resolve(regionCode: seed.regionCode)
            let user = UserEntity(
                id: "rich-user-\(seed.handle)",
                username: seed.handle,
                displayName: seed.displayName,
                avatarURL: "",
                coverURL: "",
                bio: seed.bio,
                location: seed.location,
                joinDate: .now.addingTimeInterval(Double(-index * 86400)),
                isVerified: seed.isVerified,
                role: seed.role,
                followerCount: 0,
                followingCount: 0,
                createdAt: .now,
                updatedAt: .now,
                passwordHash: "",
                avatarSymbol: avatarSymbol(forIndex: index),
                avatarColorName: avatarColor(forIndex: index),
                country: region?.countryCode ?? "",
                province: region?.provinceCode ?? "",
                city: region?.cityCode ?? "",
                currentRegionCode: region?.regionCode ?? "",
                membershipLevel: index % 9 == 0 ? "pro" : "free",
                totalHeat: Double(((index * 137) % 25000) + 500),
                creatorBadge: seed.role == .creator ? "本地创作者" : "",
                isMerchant: seed.isMerchant,
                merchantVerified: seed.isMerchant && index % 2 == 0,
                profileViewCount: ((index * 17) % 4000) + 100,
                appLanguage: seed.language,
                contentLanguagePreference: seed.language
            )
            return user
        }
    }

    private static func avatarSymbol(forIndex i: Int) -> String {
        let pool = [
            "person.fill", "sparkles", "leaf.fill", "flame.fill", "moon.stars.fill",
            "bolt.fill", "heart.fill", "music.note", "guitars.fill", "camera.fill",
            "paintbrush.pointed.fill", "books.vertical.fill", "graduationcap.fill",
            "soccerball", "fork.knife", "cup.and.saucer.fill", "airplane",
            "tree.fill", "cat.fill", "dog.fill"
        ]
        return pool[i % pool.count]
    }

    private static func avatarColor(forIndex i: Int) -> String {
        ["blue", "purple", "pink", "orange", "green", "teal", "indigo", "red", "yellow"][i % 9]
    }

    // MARK: - Posts

    private static func makePost(user: UserEntity, userIndex: Int, postIndex: Int) -> PostEntity {
        let blueprint = postBlueprint(userIndex: userIndex, postIndex: postIndex)
        let createdAt = Date.now.addingTimeInterval(Double(-(userIndex * 600 + postIndex * 1800)))
        let region = KaiXRegionDirectory.resolve(regionCode: user.currentRegionCode)
        let heat = Double(((userIndex * 7 + postIndex * 13 + blueprint.heatBoost) % 50000) + 800)

        let attributes = blueprint.attributes
        let attributesRaw = encode(attributes)

        let post = PostEntity(
            id: "rich-post-\(user.username)-\(postIndex)",
            authorId: user.id,
            content: blueprint.content,
            createdAt: createdAt,
            updatedAt: createdAt,
            commentCount: (userIndex + postIndex) % 14,
            repostCount: (userIndex + postIndex) % 8,
            likeCount: ((userIndex * 5 + postIndex * 3) % 220) + 5,
            bookmarkCount: ((userIndex * 3 + postIndex) % 50) + 1,
            viewCount: ((userIndex * 67 + postIndex * 47) % 30000) + 200,
            heatScore: heat,
            status: .published,
            hashtags: blueprint.tags,
            country: region?.countryCode ?? user.country,
            province: region?.provinceCode ?? user.province,
            city: region?.cityCode ?? user.city,
            regionCode: region?.regionCode ?? user.currentRegionCode,
            contentType: blueprint.type,
            attributesRaw: attributesRaw,
            isBoosted: userIndex % 23 == 0,
            boostWeight: userIndex % 23 == 0 ? 1.0 : 0,
            language: user.contentLanguagePreference.isEmpty ? "zh" : user.contentLanguagePreference
        )
        return post
    }

    private static func encode(_ map: [String: String]) -> String {
        guard !map.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    /// Determines the post's ContentType + body + typed attributes from
    /// stable indexes so the generator stays deterministic.
    private struct PostBlueprint {
        let type: ContentType
        let content: String
        let tags: [String]
        let attributes: [String: String]
        let heatBoost: Int
    }

    private static func postBlueprint(userIndex: Int, postIndex: Int) -> PostBlueprint {
        let mix: [PostBlueprint] = [
            // Generic dynamic
            .init(type: .dynamic, content: "今天在咖啡店窝了一下午,城市的节奏太适合深度工作了。#本地生活", tags: ["本地生活"], attributes: [:], heatBoost: 0),
            .init(type: .dynamic, content: "周末打算去逛逛新开的书店,有没有同城想一起去的朋友?", tags: ["书店", "周末"], attributes: [:], heatBoost: 50),
            .init(type: .dynamic, content: "新搬来这个城市第一天的感受:城市气质真的影响一个人的状态。#城市观察", tags: ["城市观察"], attributes: [:], heatBoost: 80),
            // Guide
            .init(type: .guide, content: "整理了本地三个月生活的清单,从看房、办卡到搬家。", tags: ["攻略", "生活指南"], attributes: [
                "title": "新人 30 天本地生活清单",
                "summary": "看房 / 银行 / 手机卡 / 交通 / 医院 一站清单"
            ], heatBoost: 220),
            .init(type: .guide, content: "学习语言这两年总结的 5 个真有用的方法。", tags: ["语言学习"], attributes: [
                "title": "语言学习 5 个真有用的方法",
                "summary": "听 / 说 / 读 / 写 / 看的实操"
            ], heatBoost: 180),
            // Secondhand
            .init(type: .secondhand, content: "出闲置 iPad 一台,9 成新,有意私聊。", tags: ["二手", "iPad"], attributes: [
                "title": "iPad Air 64G 出",
                "price": "1800",
                "currency": "CNY",
                "condition": "9 成新",
                "trade_method": "同城",
                "status": "available"
            ], heatBoost: 90),
            .init(type: .secondhand, content: "搬家出闲置咖啡机一台,意式半自动,带磨豆机。", tags: ["二手", "搬家"], attributes: [
                "title": "意式咖啡机 + 磨豆机",
                "price": "650",
                "currency": "CNY",
                "condition": "8 成新",
                "status": "available"
            ], heatBoost: 60),
            // Housing
            .init(type: .housing, content: "整租一居室,近地铁,采光好。", tags: ["租房"], attributes: [
                "title": "近地铁一居室转租",
                "rent": "4500",
                "currency": "CNY",
                "area": "市中心",
                "nearest_station": "1 号线",
                "status": "available"
            ], heatBoost: 140),
            .init(type: .housing, content: "合租找室友,2 室 1 厅其中一间,朝南。", tags: ["合租", "租房"], attributes: [
                "title": "合租找室友 朝南次卧",
                "rent": "2100",
                "currency": "CNY",
                "area": "近大学城",
                "status": "available"
            ], heatBoost: 100),
            // Job post
            .init(type: .job_post, content: "招前端工程师,React,远程可。", tags: ["招聘", "前端"], attributes: [
                "title": "前端工程师 (React)",
                "job_title": "前端工程师",
                "company_name": "本地科技公司",
                "salary": "20-35K",
                "job_type": "full_time",
                "work_location": "市中心 / 远程",
                "language_requirement": "中文 / 英语 (沟通)"
            ], heatBoost: 200),
            .init(type: .job_post, content: "本地咖啡店招兼职咖啡师,可培训。", tags: ["招聘", "兼职"], attributes: [
                "title": "咖啡店兼职咖啡师",
                "job_title": "咖啡师",
                "company_name": "城市小馆",
                "salary": "时薪 28-35",
                "job_type": "part_time",
                "work_location": "市中心"
            ], heatBoost: 60),
            // Meetup
            .init(type: .meetup, content: "周日下午约一起打球,4 人。", tags: ["搭子", "运动"], attributes: [
                "title": "周日篮球局",
                "meetup_type": "运动",
                "meetup_time": "周日 14:00",
                "location": "市民体育中心",
                "people_limit": "4"
            ], heatBoost: 110),
            .init(type: .meetup, content: "找学习搭子一起去图书馆,每周末两次。", tags: ["搭子", "学习"], attributes: [
                "title": "周末学习搭子",
                "meetup_type": "学习",
                "meetup_time": "周末 9:00-12:00",
                "location": "图书馆",
                "people_limit": "2"
            ], heatBoost: 80),
            // Dining
            .init(type: .dining, content: "周五晚上一起吃烤肉,人多更便宜。", tags: ["约饭", "烤肉"], attributes: [
                "title": "周五约烤肉",
                "restaurant_or_area": "韩餐街",
                "meetup_time": "周五 19:00",
                "people_limit": "5",
                "budget": "人均 120"
            ], heatBoost: 95),
            .init(type: .dining, content: "下班一起咖啡,聊聊本地的开发者圈子。", tags: ["约饭", "咖啡"], attributes: [
                "title": "Coffee chat",
                "restaurant_or_area": "市中心咖啡店",
                "meetup_time": "下班后",
                "people_limit": "3",
                "budget": "人均 50"
            ], heatBoost: 70),
            // Event
            .init(type: .event, content: "本地独立设计师市集,周末两天。", tags: ["活动", "市集"], attributes: [
                "title": "独立设计师市集",
                "event_time": "本周六-周日 10:00-18:00",
                "location": "市中心文创园",
                "fee": "免费",
                "capacity": "200"
            ], heatBoost: 140),
            // News
            .init(type: .news, content: "本地公交线路调整,5 条线路改道。", tags: ["新闻", "交通"], attributes: [
                "title": "5 条公交线路调整",
                "source": "本地交通广播",
                "summary": "下周一起执行,影响早高峰",
                "external_url": ""
            ], heatBoost: 250),
            // Question
            .init(type: .question, content: "请问本地办银行卡哪家比较快?", tags: ["问答", "银行卡"], attributes: [
                "question": "本地办银行卡哪家最快?",
                "category": "生活"
            ], heatBoost: 110),
            // Coupon
            .init(type: .coupon, content: "本地咖啡店第二杯半价,有效期 7 天。", tags: ["优惠", "咖啡"], attributes: [
                "title": "咖啡店第二杯半价",
                "discount_info": "第二杯半价",
                "valid_until": "本周日"
            ], heatBoost: 80),
            // Service
            .init(type: .service, content: "提供本地搬家服务,小型搬家。", tags: ["服务", "搬家"], attributes: [
                "service_type": "搬家",
                "price_range": "500-1500",
                "contact_method": "私信"
            ], heatBoost: 60),
            // Warning
            .init(type: .warning, content: "踩雷分享 — 某餐厅菜量虚标。", tags: ["避坑", "餐厅"], attributes: [
                "title": "避坑 - 餐厅菜量虚标",
                "category": "餐厅",
                "description": "实际菜量明显小于图片展示",
                "review_status": "active"
            ], heatBoost: 130),
        ]
        let index = (userIndex * 7 + postIndex * 3) % mix.count
        return mix[index]
    }

    // MARK: - User seed data

    /// 100+ users. Order matters — index drives avatar pool / heat /
    /// boost / follow graph, so re-ordering changes the demo deck.
    private static let userSeeds: [UserSeed] = [
        // CN — Beijing / Shanghai / Shenzhen / Guangzhou / Hangzhou / Chengdu / Wuhan / Nanjing / Suzhou / Xiamen
        .init(handle: "beijing_walk", displayName: "北京漫步", bio: "记录胡同与城市角落。", location: "北京", regionCode: "cn.beijing.beijing", language: "zh", isMerchant: false, isVerified: true, role: .creator),
        .init(handle: "shanghai_eats", displayName: "上海觅食", bio: "弄堂里的本帮菜,小店探店。", location: "上海", regionCode: "cn.shanghai.shanghai", language: "zh", isMerchant: true, isVerified: true, role: .creator),
        .init(handle: "shenzhen_dev", displayName: "深圳工程师", bio: "前端工程师,科技 + 城市观察。", location: "深圳", regionCode: "cn.guangdong.shenzhen", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "guangzhou_cha", displayName: "广州茶记", bio: "早茶 / 慢饮 / 巷子。", location: "广州", regionCode: "cn.guangdong.guangzhou", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "hangzhou_lake", displayName: "杭州西湖客", bio: "西湖边的工作日常。", location: "杭州", regionCode: "cn.zhejiang.hangzhou", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "chengdu_slow", displayName: "成都慢日子", bio: "茶馆、麻将、城市散步。", location: "成都", regionCode: "cn.sichuan.chengdu", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "wuhan_river", displayName: "武汉江畔", bio: "长江边上的本地观察。", location: "武汉", regionCode: "cn.hubei.wuhan", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "nanjing_bookshop", displayName: "南京书店", bio: "独立书店推介。", location: "南京", regionCode: "cn.jiangsu.nanjing", language: "zh", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "suzhou_garden", displayName: "苏州园林记", bio: "古典园林与现代生活。", location: "苏州", regionCode: "cn.jiangsu.suzhou", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "xiamen_sea", displayName: "厦门海边", bio: "海边散步与本地小店。", location: "厦门", regionCode: "cn.fujian.xiamen", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "bj_food_radar", displayName: "京食雷达", bio: "北京本地小店地图。", location: "北京", regionCode: "cn.beijing.beijing", language: "zh", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "sh_culture", displayName: "沪上文化", bio: "上海展览与文化活动。", location: "上海", regionCode: "cn.shanghai.shanghai", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "sz_startups", displayName: "深圳创业圈", bio: "本地创业、工程、产品。", location: "深圳", regionCode: "cn.guangdong.shenzhen", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "gz_market", displayName: "广州市集", bio: "本地市集与新店。", location: "广州", regionCode: "cn.guangdong.guangzhou", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "hz_dev", displayName: "杭州开发者", bio: "互联网与城市观察。", location: "杭州", regionCode: "cn.zhejiang.hangzhou", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "cd_eats", displayName: "成都食客", bio: "成都美食地图。", location: "成都", regionCode: "cn.sichuan.chengdu", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "wh_tech", displayName: "武汉科技", bio: "武汉本地科技讨论。", location: "武汉", regionCode: "cn.hubei.wuhan", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "nj_culture", displayName: "金陵文化", bio: "南京文化与历史。", location: "南京", regionCode: "cn.jiangsu.nanjing", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "sz_garden_life", displayName: "苏州生活", bio: "园林、生活、本地观察。", location: "苏州", regionCode: "cn.jiangsu.suzhou", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "xm_coffee", displayName: "厦门咖啡店", bio: "海边咖啡店推荐。", location: "厦门", regionCode: "cn.fujian.xiamen", language: "zh", isMerchant: true, isVerified: false, role: .member),
        // 拓展 CN 用户
        .init(handle: "tianjin_walk", displayName: "天津漫步", bio: "海河边的城市记。", location: "天津", regionCode: "cn.tianjin.tianjin", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "chongqing_hot", displayName: "重庆烫", bio: "山城、火锅、本地生活。", location: "重庆", regionCode: "cn.chongqing.chongqing", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "xian_history", displayName: "西安记", bio: "古都与现代生活。", location: "西安", regionCode: "cn.shaanxi.xian", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "changsha_night", displayName: "长沙夜", bio: "夜晚的城市与小吃。", location: "长沙", regionCode: "cn.hunan.changsha", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "tianjin_food", displayName: "天津食记", bio: "煎饼果子与本地味道。", location: "天津", regionCode: "cn.tianjin.tianjin", language: "zh", isMerchant: false, isVerified: false, role: .member),
        // JP — Tokyo / Osaka / Kyoto / Fukuoka / Nagoya
        .init(handle: "tokyo_walk", displayName: "東京散歩", bio: "東京の街と暮らしを記録。", location: "東京", regionCode: "jp.tokyo.tokyo", language: "ja", isMerchant: false, isVerified: true, role: .creator),
        .init(handle: "osaka_eats", displayName: "大阪グルメ", bio: "大阪の街の食。", location: "大阪", regionCode: "jp.osaka.osaka", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "kyoto_quiet", displayName: "京都散策", bio: "静かな町と寺。", location: "京都", regionCode: "jp.kyoto.kyoto", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "fukuoka_local", displayName: "福岡ライフ", bio: "福岡の店と暮らし。", location: "福岡", regionCode: "jp.fukuoka.fukuoka", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "nagoya_tech", displayName: "名古屋ITおじさん", bio: "ITエンジニア。", location: "名古屋", regionCode: "jp.aichi.nagoya", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "tokyo_visa", displayName: "東京ビザ案内", bio: "ビザと暮らしのヘルプ。", location: "東京", regionCode: "jp.tokyo.tokyo", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "osaka_jobs", displayName: "大阪求人", bio: "大阪の仕事紹介。", location: "大阪", regionCode: "jp.osaka.osaka", language: "ja", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "kyoto_temples", displayName: "京の寺町", bio: "寺・町・お茶。", location: "京都", regionCode: "jp.kyoto.kyoto", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "fukuoka_ramen", displayName: "福岡ラーメン", bio: "豚骨と街。", location: "福岡", regionCode: "jp.fukuoka.fukuoka", language: "ja", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "nagoya_food", displayName: "名古屋飯", bio: "名古屋のローカル飯。", location: "名古屋", regionCode: "jp.aichi.nagoya", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "tokyo_design", displayName: "東京デザイン", bio: "デザイン情報。", location: "東京", regionCode: "jp.tokyo.tokyo", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "tokyo_market", displayName: "東京マーケット", bio: "週末マーケット情報。", location: "東京", regionCode: "jp.tokyo.tokyo", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "osaka_streets", displayName: "大阪のまち", bio: "大阪の路地と店。", location: "大阪", regionCode: "jp.osaka.osaka", language: "ja", isMerchant: false, isVerified: false, role: .member),
        // US
        .init(handle: "nyc_runs", displayName: "NYC Runs", bio: "Runs and street food in NYC.", location: "纽约", regionCode: "us.ny.nyc", language: "en", isMerchant: false, isVerified: true, role: .creator),
        .init(handle: "la_food", displayName: "LA Food", bio: "Eats and outings in LA.", location: "洛杉矶", regionCode: "us.ca.la", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "sf_dev", displayName: "SF Dev", bio: "iOS engineer in SF.", location: "旧金山", regionCode: "us.ca.sf", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "boston_walk", displayName: "Boston Walks", bio: "Walks around Boston.", location: "波士顿", regionCode: "us.ma.boston", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "seattle_coffee", displayName: "Seattle Coffee", bio: "Coffee shops in Seattle.", location: "西雅图", regionCode: "us.wa.seattle", language: "en", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "nyc_tips", displayName: "NYC Tips", bio: "Apartment and visa tips.", location: "纽约", regionCode: "us.ny.nyc", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "la_jobs", displayName: "LA Jobs", bio: "Job posts around LA.", location: "洛杉矶", regionCode: "us.ca.la", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "sf_meetups", displayName: "SF Meetups", bio: "Meetups & community.", location: "旧金山", regionCode: "us.ca.sf", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "chicago_local", displayName: "Chicago Local", bio: "Chicago neighborhoods.", location: "芝加哥", regionCode: "us.il.chicago", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "austin_tech", displayName: "Austin Tech", bio: "Tech / startups / Austin.", location: "奥斯汀", regionCode: "us.tx.austin", language: "en", isMerchant: false, isVerified: false, role: .member),
        // UK / CA / AU / SG / KR
        .init(handle: "london_chats", displayName: "London Chats", bio: "London locals.", location: "伦敦", regionCode: "uk.london", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "manchester_life", displayName: "Manchester Life", bio: "City life Manchester.", location: "曼彻斯特", regionCode: "uk.manchester", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "edinburgh_walk", displayName: "Edinburgh Walks", bio: "Walks in Edinburgh.", location: "爱丁堡", regionCode: "uk.edinburgh", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "toronto_jobs", displayName: "Toronto Jobs", bio: "Job board around Toronto.", location: "多伦多", regionCode: "ca.toronto", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "vancouver_walk", displayName: "Vancouver Walks", bio: "Walks in Vancouver.", location: "温哥华", regionCode: "ca.vancouver", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "toronto_cafe", displayName: "Toronto Café", bio: "Café and chats around Toronto.", location: "多伦多", regionCode: "ca.toronto", language: "en", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "sydney_runs", displayName: "Sydney Runs", bio: "Runs around Sydney.", location: "悉尼", regionCode: "au.sydney", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "melbourne_food", displayName: "Melbourne Food", bio: "Eats in Melbourne.", location: "墨尔本", regionCode: "au.melbourne", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "singapore_local", displayName: "Singapore Local", bio: "Singapore life.", location: "新加坡", regionCode: "sg.singapore", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "seoul_food", displayName: "서울맛집", bio: "서울 맛집 추천.", location: "首尔", regionCode: "kr.seoul", language: "ko", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "busan_walk", displayName: "부산 산책", bio: "부산의 거리.", location: "釜山", regionCode: "kr.busan", language: "ko", isMerchant: false, isVerified: false, role: .member),
        // FR / DE / NL / TH / MY
        .init(handle: "paris_cafe", displayName: "Paris Café", bio: "Cafés et balades.", location: "巴黎", regionCode: "fr.paris", language: "fr", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "berlin_techno", displayName: "Berlin Techno", bio: "Berlin music & life.", location: "柏林", regionCode: "de.berlin", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "amsterdam_bike", displayName: "Amsterdam Bike", bio: "Bike commutes.", location: "阿姆斯特丹", regionCode: "nl.amsterdam", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "bangkok_eats", displayName: "Bangkok Eats", bio: "Bangkok street food.", location: "曼谷", regionCode: "th.bangkok", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "kl_food", displayName: "KL Food", bio: "Eats in KL.", location: "吉隆坡", regionCode: "my.kl", language: "en", isMerchant: false, isVerified: false, role: .member),
        // Extra fillers to push past 100
        .init(handle: "tokyo_visa2", displayName: "東京暮らし便利帳", bio: "暮らしのヒント。", location: "東京", regionCode: "jp.tokyo.tokyo", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "tokyo_jobs2", displayName: "東京求人板", bio: "求人ガイド。", location: "東京", regionCode: "jp.tokyo.tokyo", language: "ja", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "tokyo_food2", displayName: "東京ローカルめし", bio: "ローカル飯。", location: "東京", regionCode: "jp.tokyo.tokyo", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "tokyo_apt", displayName: "東京賃貸メモ", bio: "賃貸の情報。", location: "東京", regionCode: "jp.tokyo.tokyo", language: "ja", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "shanghai_dev", displayName: "上海开发者", bio: "iOS / React 工程师。", location: "上海", regionCode: "cn.shanghai.shanghai", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "shanghai_jobs", displayName: "上海招聘板", bio: "本地招聘汇总。", location: "上海", regionCode: "cn.shanghai.shanghai", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "shanghai_market", displayName: "上海市集", bio: "周末市集与活动。", location: "上海", regionCode: "cn.shanghai.shanghai", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "shenzhen_jobs", displayName: "深圳招聘", bio: "深圳本地招人。", location: "深圳", regionCode: "cn.guangdong.shenzhen", language: "zh", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "shenzhen_food", displayName: "深圳吃货", bio: "深圳吃喝地图。", location: "深圳", regionCode: "cn.guangdong.shenzhen", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "beijing_jobs", displayName: "北京招聘", bio: "北京招聘信息。", location: "北京", regionCode: "cn.beijing.beijing", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "beijing_rent", displayName: "北京房源", bio: "北京租房日志。", location: "北京", regionCode: "cn.beijing.beijing", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "beijing_dev", displayName: "北京工程师", bio: "技术 + 生活。", location: "北京", regionCode: "cn.beijing.beijing", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "guangzhou_jobs", displayName: "广州招聘", bio: "广州本地招人。", location: "广州", regionCode: "cn.guangdong.guangzhou", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "hangzhou_jobs", displayName: "杭州招聘", bio: "杭州本地招人。", location: "杭州", regionCode: "cn.zhejiang.hangzhou", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "hangzhou_meetup", displayName: "杭州搭子", bio: "杭州学习搭子。", location: "杭州", regionCode: "cn.zhejiang.hangzhou", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "chengdu_meetup", displayName: "成都搭子", bio: "约饭约咖啡。", location: "成都", regionCode: "cn.sichuan.chengdu", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "chengdu_jobs", displayName: "成都招聘", bio: "成都本地招人。", location: "成都", regionCode: "cn.sichuan.chengdu", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "wuhan_food", displayName: "武汉美食", bio: "热干面与本地味道。", location: "武汉", regionCode: "cn.hubei.wuhan", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "nanjing_jobs", displayName: "南京招聘", bio: "南京本地招人。", location: "南京", regionCode: "cn.jiangsu.nanjing", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "suzhou_meetup", displayName: "苏州搭子", bio: "苏州学习搭子。", location: "苏州", regionCode: "cn.jiangsu.suzhou", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "xiamen_jobs", displayName: "厦门招聘", bio: "厦门本地招人。", location: "厦门", regionCode: "cn.fujian.xiamen", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "nyc_food", displayName: "NYC Eats", bio: "NYC food spots.", location: "纽约", regionCode: "us.ny.nyc", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "la_meetups", displayName: "LA Meetups", bio: "Meetups in LA.", location: "洛杉矶", regionCode: "us.ca.la", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "sf_walks", displayName: "SF Walks", bio: "City walks SF.", location: "旧金山", regionCode: "us.ca.sf", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "london_jobs", displayName: "London Jobs", bio: "Jobs in London.", location: "伦敦", regionCode: "uk.london", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "london_food", displayName: "London Food", bio: "London food spots.", location: "伦敦", regionCode: "uk.london", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "toronto_food", displayName: "Toronto Food", bio: "Toronto food.", location: "多伦多", regionCode: "ca.toronto", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "vancouver_jobs", displayName: "Vancouver Jobs", bio: "Jobs Vancouver.", location: "温哥华", regionCode: "ca.vancouver", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "vancouver_food", displayName: "Vancouver Eats", bio: "Eats Vancouver.", location: "温哥华", regionCode: "ca.vancouver", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "toronto_hiring", displayName: "Toronto Hiring", bio: "Hiring around Toronto.", location: "多伦多", regionCode: "ca.toronto", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "sydney_food", displayName: "Sydney Eats", bio: "Eats around Sydney.", location: "悉尼", regionCode: "au.sydney", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "sydney_meetup", displayName: "Sydney Meetups", bio: "Meetups Sydney.", location: "悉尼", regionCode: "au.sydney", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "melbourne_jobs", displayName: "Melbourne Jobs", bio: "Jobs in Melbourne.", location: "墨尔本", regionCode: "au.melbourne", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "singapore_food", displayName: "SG Eats", bio: "Singapore food.", location: "新加坡", regionCode: "sg.singapore", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "singapore_jobs", displayName: "SG Jobs", bio: "Singapore jobs.", location: "新加坡", regionCode: "sg.singapore", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "seoul_food2", displayName: "서울 음식 일지", bio: "서울 골목 음식.", location: "首尔", regionCode: "kr.seoul", language: "ko", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "paris_food", displayName: "Paris Eats", bio: "Bistros et boulangeries.", location: "巴黎", regionCode: "fr.paris", language: "fr", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "berlin_jobs", displayName: "Berlin Jobs", bio: "Jobs in Berlin.", location: "柏林", regionCode: "de.berlin", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "amsterdam_food", displayName: "Amsterdam Food", bio: "Eats in Amsterdam.", location: "阿姆斯特丹", regionCode: "nl.amsterdam", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "bangkok_food", displayName: "Bangkok Food", bio: "Bangkok food map.", location: "曼谷", regionCode: "th.bangkok", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "kl_jobs", displayName: "KL Jobs", bio: "Jobs in KL.", location: "吉隆坡", regionCode: "my.kl", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "kaifa_share", displayName: "开发者札记", bio: "开发与生活笔记。", location: "深圳", regionCode: "cn.guangdong.shenzhen", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "japan_apt_guide", displayName: "日本租房指南", bio: "日本租房经验。", location: "东京", regionCode: "jp.tokyo.tokyo", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "japan_visa", displayName: "日本签证助手", bio: "签证 / 工作 / 留学。", location: "东京", regionCode: "jp.tokyo.tokyo", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "us_apt_guide", displayName: "美国租房指南", bio: "美国租房经验。", location: "纽约", regionCode: "us.ny.nyc", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "ca_immigration", displayName: "加拿大移民笔记", bio: "Express Entry 与生活。", location: "多伦多", regionCode: "ca.toronto", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "uk_study", displayName: "英国留学日记", bio: "本科与硕士经验。", location: "伦敦", regionCode: "uk.london", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "au_pr", displayName: "澳洲 PR 笔记", bio: "签证、PR、就业。", location: "悉尼", regionCode: "au.sydney", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "sg_work", displayName: "新加坡工作指南", bio: "EP / PR / 生活成本。", location: "新加坡", regionCode: "sg.singapore", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "global_grad", displayName: "全球毕业生", bio: "海外求学求职。", location: "纽约", regionCode: "us.ny.nyc", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "tokyo_japanese", displayName: "東京日本語教室", bio: "日本語学習。", location: "东京", regionCode: "jp.tokyo.tokyo", language: "ja", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "city_observer", displayName: "城市观察者", bio: "全球城市笔记。", location: "上海", regionCode: "cn.shanghai.shanghai", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "indie_designer", displayName: "独立设计师", bio: "设计 / 字体 / 海报。", location: "杭州", regionCode: "cn.zhejiang.hangzhou", language: "zh", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "indie_dev", displayName: "独立开发者", bio: "构建有趣的小东西。", location: "深圳", regionCode: "cn.guangdong.shenzhen", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "music_walk", displayName: "音乐与散步", bio: "Live house 笔记。", location: "上海", regionCode: "cn.shanghai.shanghai", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "film_diary", displayName: "电影日记", bio: "本周末看了什么。", location: "北京", regionCode: "cn.beijing.beijing", language: "zh", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "vegan_jp", displayName: "Tokyo Vegan", bio: "Vegan spots in Tokyo.", location: "东京", regionCode: "jp.tokyo.tokyo", language: "en", isMerchant: false, isVerified: false, role: .member),
        .init(handle: "yoga_shanghai", displayName: "上海瑜伽日志", bio: "瑜伽 / 健身 / 生活。", location: "上海", regionCode: "cn.shanghai.shanghai", language: "zh", isMerchant: true, isVerified: false, role: .member),
        .init(handle: "weekend_market_jp", displayName: "週末マーケット", bio: "東京の週末イベント。", location: "东京", regionCode: "jp.tokyo.tokyo", language: "ja", isMerchant: false, isVerified: false, role: .member),
    ]
}
