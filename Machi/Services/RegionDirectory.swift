import Foundation

/// Local mirror of the server's region tree (see `web/server.py`'s
/// `REGION_*` constants and `POPULAR_CITIES`).
///
/// This exists so the App can render the region picker, post composer,
/// and city chips without depending on a network round-trip. The
/// canonical source of truth is the server — when the App is online
/// it should call `KaiXAPIClient.popularRegions()` etc. and prefer
/// those results — but the directory below lets the UI stay
/// responsive offline, on first launch, and during region selection
/// where 100 ms of latency feels broken.
///
/// **Sync discipline:** whenever the server's `REGION_*` constants
/// change, mirror the change here. The pair is intentionally small
/// (few hundred lines, all literals) so this is a tractable manual
/// sync. The compiled-in copy is treated as a "default seed"; the
/// network response wins when it disagrees.
enum KaiXRegionDirectory {
    struct Country: Identifiable, Hashable {
        let code: String
        let name: String
        let emoji: String
        let tier: Int
        let hasProvinces: Bool
        var id: String { code }
    }
    struct Province: Identifiable, Hashable {
        let code: String
        let name: String
        var id: String { code }
    }
    struct City: Identifiable, Hashable {
        let code: String
        let name: String
        var id: String { code }
    }
    struct Region: Identifiable, Hashable {
        let regionCode: String
        let countryCode: String
        let countryName: String
        let countryEmoji: String
        let provinceCode: String
        let provinceName: String
        let cityCode: String
        let cityName: String
        var id: String { regionCode }

        /// "上海" / "东京" / "纽约 · NY" — short label used on chips.
        var shortLabel: String {
            if !provinceName.isEmpty && provinceCode != cityCode {
                return "\(provinceName) · \(cityName)"
            }
            return cityName
        }

        /// "🇨🇳 上海" — used in headers and the picker landing page.
        var headerLabel: String {
            "\(countryEmoji) \(cityName)"
        }

        /// Display label for local-life surfaces where country /
        /// province / city context should be explicit.
        var displayName: String {
            if provinceName.isEmpty || provinceName == cityName || provinceCode == cityCode {
                return "\(countryName) · \(cityName)"
            }
            return "\(countryName) · \(provinceName) · \(cityName)"
        }

        var flagEmoji: String { countryEmoji }

        var isHot: Bool {
            KaiXRegionDirectory.popularRegionCodes.contains(regionCode)
        }
    }

    // MARK: - Static directory

    static let countries: [Country] = [
        .init(code: "cn", name: "中国",     emoji: "🇨🇳", tier: 1, hasProvinces: true),
        .init(code: "jp", name: "日本",     emoji: "🇯🇵", tier: 1, hasProvinces: true),
        .init(code: "us", name: "美国",     emoji: "🇺🇸", tier: 1, hasProvinces: true),
        .init(code: "sg", name: "新加坡",   emoji: "🇸🇬", tier: 2, hasProvinces: false),
        .init(code: "kr", name: "韩国",     emoji: "🇰🇷", tier: 2, hasProvinces: false),
        .init(code: "uk", name: "英国",     emoji: "🇬🇧", tier: 2, hasProvinces: false),
        .init(code: "fr", name: "法国",     emoji: "🇫🇷", tier: 2, hasProvinces: false),
        .init(code: "au", name: "澳大利亚", emoji: "🇦🇺", tier: 2, hasProvinces: false),
        .init(code: "ca", name: "加拿大",   emoji: "🇨🇦", tier: 2, hasProvinces: false),
        .init(code: "th", name: "泰国",     emoji: "🇹🇭", tier: 3, hasProvinces: false),
        .init(code: "my", name: "马来西亚", emoji: "🇲🇾", tier: 3, hasProvinces: false),
        .init(code: "de", name: "德国",     emoji: "🇩🇪", tier: 3, hasProvinces: false),
        .init(code: "nl", name: "荷兰",     emoji: "🇳🇱", tier: 3, hasProvinces: false),
    ]

    static let provincesByCountry: [String: [Province]] = [
        "cn": [
            .init(code: "beijing", name: "北京"), .init(code: "shanghai", name: "上海"),
            .init(code: "tianjin", name: "天津"), .init(code: "chongqing", name: "重庆"),
            .init(code: "zhejiang", name: "浙江"), .init(code: "jiangsu", name: "江苏"),
            .init(code: "guangdong", name: "广东"), .init(code: "hongkong", name: "香港"),
            .init(code: "sichuan", name: "四川"), .init(code: "shandong", name: "山东"),
            .init(code: "fujian", name: "福建"), .init(code: "henan", name: "河南"),
            .init(code: "anhui", name: "安徽"),
            .init(code: "hunan", name: "湖南"), .init(code: "shaanxi", name: "陕西"),
            .init(code: "hubei", name: "湖北"),
        ],
        "jp": [
            .init(code: "tokyo", name: "东京都"), .init(code: "osaka", name: "大阪府"),
            .init(code: "kyoto", name: "京都府"), .init(code: "fukuoka", name: "福冈县"),
            .init(code: "aichi", name: "爱知县"),
            .init(code: "kanagawa", name: "神奈川县"), .init(code: "saitama", name: "埼玉县"),
            .init(code: "chiba", name: "千叶县"), .init(code: "hyogo", name: "兵库县"),
            .init(code: "hokkaido", name: "北海道"), .init(code: "miyagi", name: "宫城县"),
            .init(code: "hiroshima", name: "广岛县"), .init(code: "okinawa", name: "冲绳县"),
            .init(code: "shizuoka", name: "静冈县"), .init(code: "ibaraki", name: "茨城县"),
            .init(code: "nara", name: "奈良县"), .init(code: "mie", name: "三重县"),
            .init(code: "kumamoto", name: "熊本县"), .init(code: "kagoshima", name: "鹿儿岛县"),
            .init(code: "nagano", name: "长野县"), .init(code: "ishikawa", name: "石川县"),
            .init(code: "okayama", name: "冈山县"), .init(code: "niigata", name: "新潟县"),
            .init(code: "tochigi", name: "栃木县"), .init(code: "gunma", name: "群马县"),
            .init(code: "shiga", name: "滋贺县"), .init(code: "gifu", name: "岐阜县"),
            // ---- remaining prefectures (complete 47 都道府县) ----
            .init(code: "aomori", name: "青森县"), .init(code: "iwate", name: "岩手县"),
            .init(code: "akita", name: "秋田县"), .init(code: "yamagata", name: "山形县"),
            .init(code: "fukushima", name: "福岛县"), .init(code: "toyama", name: "富山县"),
            .init(code: "fukui", name: "福井县"), .init(code: "yamanashi", name: "山梨县"),
            .init(code: "wakayama", name: "和歌山县"), .init(code: "tottori", name: "鸟取县"),
            .init(code: "shimane", name: "岛根县"), .init(code: "yamaguchi", name: "山口县"),
            .init(code: "tokushima", name: "德岛县"), .init(code: "kagawa", name: "香川县"),
            .init(code: "ehime", name: "爱媛县"), .init(code: "kochi", name: "高知县"),
            .init(code: "saga", name: "佐贺县"), .init(code: "nagasaki", name: "长崎县"),
            .init(code: "oita", name: "大分县"), .init(code: "miyazaki", name: "宫崎县"),
        ],
        "us": [
            .init(code: "ca", name: "加利福尼亚"), .init(code: "ny", name: "纽约"),
            .init(code: "wa", name: "华盛顿"), .init(code: "tx", name: "德克萨斯"),
            .init(code: "fl", name: "佛罗里达"), .init(code: "il", name: "伊利诺伊"),
            .init(code: "ma", name: "马萨诸塞"), .init(code: "nj", name: "新泽西"),
        ],
    ]

    /// Parent-keyed cities. The parent is the province slug for
    /// hierarchical countries, the country code for flat ones. The
    /// special key `"ca_flat"` disambiguates Canada from California.
    static let citiesByParent: [String: [City]] = [
        // CN by province
        "shanghai": [.init(code: "shanghai", name: "上海")],
        "beijing":  [.init(code: "beijing",  name: "北京")],
        "tianjin":  [.init(code: "tianjin",  name: "天津")],
        "chongqing":[.init(code: "chongqing", name: "重庆")],
        "zhejiang":[.init(code: "hangzhou", name: "杭州"), .init(code: "ningbo", name: "宁波")],
        "jiangsu":  [.init(code: "nanjing", name: "南京"), .init(code: "suzhou", name: "苏州")],
        "guangdong":[
            .init(code: "guangzhou", name: "广州"), .init(code: "shenzhen", name: "深圳"),
            .init(code: "foshan", name: "佛山"), .init(code: "dongguan", name: "东莞"),
        ],
        "sichuan":  [.init(code: "chengdu", name: "成都")],
        "shandong": [.init(code: "qingdao", name: "青岛")],
        "fujian":   [.init(code: "xiamen", name: "厦门")],
        "henan":    [.init(code: "zhengzhou", name: "郑州")],
        "anhui":    [.init(code: "hefei", name: "合肥")],
        "hubei":    [.init(code: "wuhan", name: "武汉")],
        "shaanxi":  [.init(code: "xian", name: "西安")],
        "hunan":    [.init(code: "changsha", name: "长沙")],
        "hongkong": [.init(code: "hongkong", name: "香港")],
        // JP by prefecture
        "tokyo":    [.init(code: "tokyo", name: "东京"), .init(code: "hachioji", name: "八王子"),
                     .init(code: "machida", name: "町田"), .init(code: "tachikawa", name: "立川"),
                     .init(code: "musashino", name: "武藏野")],
        "osaka":    [.init(code: "osaka", name: "大阪"), .init(code: "sakai", name: "堺"),
                     .init(code: "suita", name: "吹田"), .init(code: "toyonaka", name: "丰中"),
                     .init(code: "higashiosaka", name: "东大阪")],
        "kyoto":    [.init(code: "kyoto", name: "京都"), .init(code: "uji", name: "宇治")],
        "fukuoka":  [.init(code: "fukuoka", name: "福冈"), .init(code: "kitakyushu", name: "北九州"),
                     .init(code: "kurume", name: "久留米")],
        "aichi":    [.init(code: "nagoya", name: "名古屋"), .init(code: "toyota", name: "丰田"),
                     .init(code: "okazaki", name: "冈崎"), .init(code: "ichinomiya", name: "一宫")],
        "kanagawa": [.init(code: "yokohama", name: "横滨"), .init(code: "kawasaki", name: "川崎"),
                     .init(code: "sagamihara", name: "相模原"), .init(code: "kamakura", name: "镰仓"),
                     .init(code: "fujisawa", name: "藤泽"), .init(code: "yokosuka", name: "横须贺")],
        "saitama":  [.init(code: "saitama", name: "埼玉"), .init(code: "kawaguchi", name: "川口"),
                     .init(code: "kawagoe", name: "川越"), .init(code: "tokorozawa", name: "所泽"),
                     .init(code: "koshigaya", name: "越谷")],
        "chiba":    [.init(code: "chiba", name: "千叶"), .init(code: "funabashi", name: "船桥"),
                     .init(code: "matsudo", name: "松户"), .init(code: "kashiwa", name: "柏"),
                     .init(code: "ichikawa", name: "市川"), .init(code: "narita", name: "成田")],
        "hyogo":    [.init(code: "kobe", name: "神户"), .init(code: "nishinomiya", name: "西宫"),
                     .init(code: "himeji", name: "姬路"), .init(code: "amagasaki", name: "尼崎")],
        "hokkaido": [.init(code: "sapporo", name: "札幌"), .init(code: "asahikawa", name: "旭川"),
                     .init(code: "hakodate", name: "函馆")],
        "miyagi":   [.init(code: "sendai", name: "仙台"), .init(code: "ishinomaki", name: "石卷")],
        "hiroshima":[.init(code: "hiroshima", name: "广岛"), .init(code: "fukuyama", name: "福山")],
        "okinawa":  [.init(code: "naha", name: "那霸"), .init(code: "okinawa", name: "冲绳")],
        "shizuoka": [.init(code: "shizuoka", name: "静冈"), .init(code: "hamamatsu", name: "滨松"),
                     .init(code: "numazu", name: "沼津")],
        "ibaraki":  [.init(code: "tsukuba", name: "筑波"), .init(code: "mito", name: "水户"),
                     .init(code: "hitachinaka", name: "常陆那珂")],
        "nara":     [.init(code: "nara", name: "奈良"), .init(code: "ikoma", name: "生驹")],
        "mie":      [.init(code: "yokkaichi", name: "四日市"), .init(code: "tsu", name: "津")],
        "kumamoto": [.init(code: "kumamoto", name: "熊本")],
        "kagoshima":[.init(code: "kagoshima", name: "鹿儿岛")],
        "nagano":   [.init(code: "nagano", name: "长野"), .init(code: "matsumoto", name: "松本")],
        "ishikawa": [.init(code: "kanazawa", name: "金泽"), .init(code: "komatsu", name: "小松")],
        "okayama":  [.init(code: "okayama", name: "冈山"), .init(code: "kurashiki", name: "仓敷")],
        "niigata":  [.init(code: "niigata", name: "新潟"), .init(code: "nagaoka", name: "长冈")],
        "tochigi":  [.init(code: "utsunomiya", name: "宇都宫"), .init(code: "oyama", name: "小山")],
        "gunma":    [.init(code: "takasaki", name: "高崎"), .init(code: "maebashi", name: "前桥")],
        "shiga":    [.init(code: "otsu", name: "大津"), .init(code: "kusatsu", name: "草津")],
        "gifu":     [.init(code: "gifu", name: "岐阜"), .init(code: "ogaki", name: "大垣")],
        // Japan: remaining prefectures (complete 47)
        "aomori":    [.init(code: "aomori", name: "青森"), .init(code: "hachinohe", name: "八户")],
        "iwate":     [.init(code: "morioka", name: "盛冈"), .init(code: "ichinoseki", name: "一关")],
        "akita":     [.init(code: "akita", name: "秋田")],
        "yamagata":  [.init(code: "yamagata", name: "山形"), .init(code: "tsuruoka", name: "鹤冈")],
        "fukushima": [.init(code: "fukushima", name: "福岛"), .init(code: "koriyama", name: "郡山"), .init(code: "iwaki", name: "磐城")],
        "toyama":    [.init(code: "toyama", name: "富山"), .init(code: "takaoka", name: "高冈")],
        "fukui":     [.init(code: "fukui", name: "福井")],
        "yamanashi": [.init(code: "kofu", name: "甲府")],
        "wakayama":  [.init(code: "wakayama", name: "和歌山")],
        "tottori":   [.init(code: "tottori", name: "鸟取"), .init(code: "yonago", name: "米子")],
        "shimane":   [.init(code: "matsue", name: "松江"), .init(code: "izumo", name: "出云")],
        "yamaguchi": [.init(code: "yamaguchi", name: "山口"), .init(code: "shimonoseki", name: "下关")],
        "tokushima": [.init(code: "tokushima", name: "德岛")],
        "kagawa":    [.init(code: "takamatsu", name: "高松")],
        "ehime":     [.init(code: "matsuyama", name: "松山"), .init(code: "imabari", name: "今治")],
        "kochi":     [.init(code: "kochi", name: "高知")],
        "saga":      [.init(code: "saga", name: "佐贺")],
        "nagasaki":  [.init(code: "nagasaki", name: "长崎"), .init(code: "sasebo", name: "佐世保")],
        "oita":      [.init(code: "oita", name: "大分"), .init(code: "beppu", name: "别府")],
        "miyazaki":  [.init(code: "miyazaki", name: "宫崎")],
        // US by state
        "ca":     [.init(code: "sf", name: "旧金山"), .init(code: "la", name: "洛杉矶"),
                   .init(code: "sd", name: "圣地亚哥"), .init(code: "sj", name: "圣何塞"),
                   .init(code: "irvine", name: "尔湾")],
        "ny":     [.init(code: "nyc", name: "纽约"), .init(code: "buffalo", name: "布法罗")],
        "wa":     [.init(code: "seattle", name: "西雅图"), .init(code: "bellevue", name: "贝尔维尤")],
        "tx":     [.init(code: "austin", name: "奥斯汀"), .init(code: "houston", name: "休斯顿"),
                   .init(code: "dallas", name: "达拉斯")],
        "fl":     [.init(code: "miami", name: "迈阿密"), .init(code: "orlando", name: "奥兰多")],
        "il":     [.init(code: "chicago", name: "芝加哥")],
        "ma":     [.init(code: "boston", name: "波士顿")],
        "nj":     [.init(code: "newark", name: "纽瓦克")],
        // Flat countries
        "uk":      [
            .init(code: "london", name: "伦敦"), .init(code: "manchester", name: "曼彻斯特"),
            .init(code: "edinburgh", name: "爱丁堡"), .init(code: "birmingham", name: "伯明翰"),
            .init(code: "glasgow", name: "格拉斯哥"), .init(code: "liverpool", name: "利物浦"),
            .init(code: "leeds", name: "利兹"), .init(code: "bristol", name: "布里斯托"),
            .init(code: "cambridge", name: "剑桥"), .init(code: "oxford", name: "牛津"),
        ],
        "ca_flat": [.init(code: "toronto", name: "多伦多"), .init(code: "vancouver", name: "温哥华"), .init(code: "montreal", name: "蒙特利尔")],
        "au":      [.init(code: "sydney", name: "悉尼"), .init(code: "melbourne", name: "墨尔本"),
                    .init(code: "brisbane", name: "布里斯班"), .init(code: "perth", name: "珀斯"),
                    .init(code: "adelaide", name: "阿德莱德"), .init(code: "canberra", name: "堪培拉"),
                    .init(code: "goldcoast", name: "黄金海岸")],
        "sg":      [.init(code: "singapore", name: "新加坡")],
        "kr":      [.init(code: "seoul", name: "首尔"), .init(code: "busan", name: "釜山"),
                    .init(code: "incheon", name: "仁川"), .init(code: "daegu", name: "大邱"),
                    .init(code: "daejeon", name: "大田"), .init(code: "gwangju", name: "光州")],
        "th":      [.init(code: "bangkok", name: "曼谷"), .init(code: "chiangmai", name: "清迈"),
                    .init(code: "phuket", name: "普吉")],
        "my":      [.init(code: "kl", name: "吉隆坡"), .init(code: "penang", name: "槟城")],
        "de":      [.init(code: "berlin", name: "柏林"), .init(code: "munich", name: "慕尼黑"),
                    .init(code: "hamburg", name: "汉堡")],
        "fr":      [.init(code: "paris", name: "巴黎"), .init(code: "lyon", name: "里昂"),
                    .init(code: "marseille", name: "马赛"), .init(code: "toulouse", name: "图卢兹"),
                    .init(code: "nice", name: "尼斯"), .init(code: "bordeaux", name: "波尔多")],
        "nl":      [.init(code: "amsterdam", name: "阿姆斯特丹")],
    ]

    /// Region codes for the "hot cities" shortcut on the picker.
    /// MUST stay in sync with `POPULAR_CITIES` in `web/server.py`.
    /// Curated for KaiX's audience: domestic launch cities + the
    /// overseas metros with the largest Chinese diaspora.
    static let popularRegionCodes: [String] = [
        // China
        "cn.shanghai.shanghai", "cn.beijing.beijing",
        "cn.guangdong.shenzhen", "cn.guangdong.guangzhou",
        "cn.zhejiang.hangzhou", "cn.sichuan.chengdu",
        "cn.chongqing.chongqing", "cn.hubei.wuhan",
        "cn.jiangsu.nanjing", "cn.jiangsu.suzhou",
        "cn.shaanxi.xian", "cn.hunan.changsha",
        "cn.shandong.qingdao", "cn.fujian.xiamen",
        "cn.tianjin.tianjin", "cn.henan.zhengzhou",
        "cn.zhejiang.ningbo", "cn.guangdong.foshan",
        "cn.guangdong.dongguan", "cn.anhui.hefei",
        // Japan
        "jp.tokyo.tokyo", "jp.osaka.osaka",
        "jp.kyoto.kyoto", "jp.fukuoka.fukuoka", "jp.aichi.nagoya",
        "jp.kanagawa.yokohama", "jp.kanagawa.kawasaki",
        "jp.kanagawa.sagamihara", "jp.kanagawa.kamakura",
        "jp.saitama.saitama", "jp.saitama.kawaguchi",
        "jp.chiba.chiba", "jp.chiba.funabashi",
        "jp.hyogo.kobe", "jp.hyogo.nishinomiya",
        "jp.hokkaido.sapporo", "jp.hokkaido.asahikawa",
        "jp.miyagi.sendai", "jp.hiroshima.hiroshima",
        "jp.fukuoka.kitakyushu", "jp.okinawa.naha", "jp.shizuoka.shizuoka",
        // US
        "us.ny.nyc", "us.ca.la", "us.ca.sf", "us.wa.seattle",
        // Canada
        "ca.toronto", "ca.vancouver", "ca.montreal",
        // Australia
        "au.sydney", "au.melbourne",
        // UK
        "uk.london",
        // France
        "fr.paris",
        // Other Asia / SEA
        "sg.singapore", "kr.seoul",
        "th.bangkok",
    ]

    // MARK: - Lookups

    static func country(code: String) -> Country? {
        countries.first { $0.code == code.lowercased() }
    }

    /// Country display names for the three app languages. The directory's
    /// own `name` field is the zh form; ja/en live here so pickers stop
    /// falling back to hardcoded English.
    private static let countryNamesJaEn: [String: (ja: String, en: String)] = [
        "cn": ("中国", "China"), "jp": ("日本", "Japan"), "us": ("アメリカ", "United States"),
        "sg": ("シンガポール", "Singapore"), "kr": ("韓国", "South Korea"), "uk": ("イギリス", "United Kingdom"),
        "fr": ("フランス", "France"), "au": ("オーストラリア", "Australia"), "ca": ("カナダ", "Canada"),
        "th": ("タイ", "Thailand"), "my": ("マレーシア", "Malaysia"), "de": ("ドイツ", "Germany"),
        "nl": ("オランダ", "Netherlands"),
    ]

    static func localizedCountryName(code: String, language: AppLanguage) -> String {
        let c = code.lowercased()
        let zh = country(code: c)?.name ?? c.uppercased()
        guard let names = countryNamesJaEn[c] else { return zh }
        switch language {
        case .ja: return names.ja
        case .en: return names.en
        case .zh, .system: return zh
        }
    }

    /// The country's most popular city (first popular entry, else the first
    /// directory city) — where a bare country switch should land.
    static func defaultRegionCode(forCountry code: String) -> String? {
        let c = code.lowercased()
        if let popular = popularRegionCodes.first(where: { $0.hasPrefix(c + ".") }) {
            return popular
        }
        if country(code: c)?.hasProvinces == true {
            guard let province = provinces(for: c).first,
                  let city = cities(country: c, province: province.code).first else { return nil }
            return "\(c).\(province.code).\(city.code)"
        }
        guard let city = cities(country: c, province: nil).first else { return nil }
        return "\(c).\(city.code)"
    }

    static func provinces(for country: String) -> [Province] {
        provincesByCountry[country.lowercased()] ?? []
    }

    static func cities(country: String, province: String?) -> [City] {
        let c = country.lowercased()
        if let p = province, !p.isEmpty {
            let parent = p.lowercased()
            if Self.country(code: c)?.hasProvinces == true,
               !provinces(for: c).contains(where: { $0.code == parent }) {
                return []
            }
            return citiesByParent[parent] ?? []
        }
        // Canada flat-country lookup needs the disambiguating key.
        if c == "ca" { return citiesByParent["ca_flat"] ?? [] }
        return citiesByParent[c] ?? []
    }

    // 日本「都市圈」分组：选地区时按生活圈聚合（关东圈/关西圈/名古屋…），
    // 与 Web regions.ts 的 JP_METRO_CIRCLES 保持一致。
    struct MetroCircle: Identifiable, Hashable {
        let code: String
        let name: String
        let provinceCodes: [String]
        var id: String { code }
    }

    static let jpMetroCircles: [MetroCircle] = [
        .init(code: "hokkaido_tohoku", name: "北海道・东北", provinceCodes: ["hokkaido", "aomori", "iwate", "miyagi", "akita", "yamagata", "fukushima"]),
        .init(code: "kanto", name: "关东", provinceCodes: ["ibaraki", "tochigi", "gunma", "saitama", "chiba", "tokyo", "kanagawa"]),
        .init(code: "chubu", name: "中部", provinceCodes: ["niigata", "toyama", "ishikawa", "fukui", "yamanashi", "nagano", "gifu", "shizuoka", "aichi"]),
        .init(code: "kansai", name: "近畿・关西", provinceCodes: ["mie", "shiga", "kyoto", "osaka", "hyogo", "nara", "wakayama"]),
        .init(code: "chugoku", name: "中国地区", provinceCodes: ["tottori", "shimane", "okayama", "hiroshima", "yamaguchi"]),
        .init(code: "shikoku", name: "四国", provinceCodes: ["tokushima", "kagawa", "ehime", "kochi"]),
        .init(code: "kyushu_okinawa", name: "九州・冲绳", provinceCodes: ["fukuoka", "saga", "nagasaki", "kumamoto", "oita", "miyazaki", "kagoshima", "okinawa"]),
    ]

    /// (province, city-region) pairs for every city inside a JP metro circle.
    static func regionsForMetroCircle(_ circleCode: String) -> [(province: Province, region: Region)] {
        guard let circle = jpMetroCircles.first(where: { $0.code == circleCode }) else { return [] }
        var out: [(Province, Region)] = []
        for provinceCode in circle.provinceCodes {
            guard let province = provinces(for: "jp").first(where: { $0.code == provinceCode }) else { continue }
            for city in cities(country: "jp", province: provinceCode) {
                if let region = make(country: "jp", province: provinceCode, city: city.code) {
                    out.append((province, region))
                }
            }
        }
        return out
    }

    static func metroCircle(for region: Region?) -> MetroCircle? {
        guard let region, region.countryCode == "jp" else { return nil }
        return jpMetroCircles.first { $0.provinceCodes.contains(region.provinceCode) }
    }

    static func regionsForMetro(region: Region?) -> [Region] {
        guard let region else { return [] }
        guard let circle = metroCircle(for: region) else { return [region] }
        let regions = regionsForMetroCircle(circle.code).map(\.region)
        return regions.isEmpty ? [region] : regions
    }

    static func regionCodesForMetro(region: Region?) -> [String] {
        regionsForMetro(region: region).map(\.regionCode)
    }

    static func cityCodesForMetro(region: Region?) -> [String] {
        regionsForMetro(region: region).map(\.cityCode)
    }

    /// Single source of truth for a JP metro circle's trilingual display name,
    /// keyed by the codes in `jpMetroCircles`. RegionPickerView, the circle
    /// drill-down title, and `localizedMetroName` must all route through here so
    /// the zh/ja/en names can never drift out of sync with the circle codes
    /// again (an earlier code rename left `localizedMetroName` matching stale
    /// `nagoya/fukuoka/…` codes, degrading every non-Kanto/Kansai circle to
    /// "その他都市/Other cities").
    static func localizedMetroCircleName(_ code: String, language: AppLanguage) -> String {
        switch code {
        case "hokkaido_tohoku":
            switch language {
            case .ja: return "北海道・東北"
            case .en: return "Hokkaido / Tohoku"
            default: return "北海道・东北"
            }
        case "kanto":
            switch language {
            case .ja: return "関東"
            case .en: return "Kanto"
            default: return "关东"
            }
        case "chubu":
            switch language {
            case .ja: return "中部"
            case .en: return "Chubu"
            default: return "中部"
            }
        case "kansai":
            switch language {
            case .ja: return "近畿・関西"
            case .en: return "Kansai"
            default: return "近畿・关西"
            }
        case "chugoku":
            switch language {
            case .ja: return "中国地方"
            case .en: return "Chugoku"
            default: return "中国地区"
            }
        case "shikoku":
            switch language {
            case .ja: return "四国"
            case .en: return "Shikoku"
            default: return "四国"
            }
        case "kyushu_okinawa":
            switch language {
            case .ja: return "九州・沖縄"
            case .en: return "Kyushu / Okinawa"
            default: return "九州・冲绳"
            }
        default:
            return jpMetroCircles.first { $0.code == code }?.name ?? code
        }
    }

    static func localizedMetroName(for region: Region?, language: AppLanguage) -> String? {
        guard let region else { return nil }
        guard let circle = metroCircle(for: region) else {
            return localizedShortLabel(region, language: language)
        }
        return localizedMetroCircleName(circle.code, language: language)
    }

    static func resolve(regionCode: String) -> Region? {
        let parts = regionCode.lowercased().split(separator: ".").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let countryCode = parts[0]
        let provinceCode = parts.count == 3 ? parts[1] : ""
        let cityCode = parts.last ?? ""
        guard let country = country(code: countryCode) else { return nil }
        var provinceName = ""
        if country.hasProvinces {
            guard !provinceCode.isEmpty,
                  let province = provinces(for: countryCode).first(where: { $0.code == provinceCode }) else {
                return nil
            }
            provinceName = province.name
        }
        guard let city = cities(country: countryCode, province: provinceCode.isEmpty ? nil : provinceCode)
            .first(where: { $0.code == cityCode }) else {
            return nil
        }
        let cityName = city.name
        return Region(
            regionCode: regionCode,
            countryCode: countryCode,
            countryName: country.name,
            countryEmoji: country.emoji,
            provinceCode: provinceCode,
            provinceName: provinceName,
            cityCode: cityCode,
            cityName: cityName
        )
    }

    static func make(country: String, province: String?, city: String) -> Region? {
        let regionCode = composeRegionCode(country: country, province: province, city: city)
        return resolve(regionCode: regionCode)
    }

    static func composeRegionCode(country: String, province: String?, city: String) -> String {
        let c = country.lowercased()
        let ci = city.lowercased()
        guard !c.isEmpty, !ci.isEmpty else { return "" }
        if let spec = Self.country(code: c), spec.hasProvinces, let p = province?.lowercased(), !p.isEmpty {
            return "\(c).\(p).\(ci)"
        }
        return "\(c).\(ci)"
    }

    // MARK: - Reverse-geocode matching (auto location)

    /// ISO country codes that differ from our internal slugs.
    private static let isoCountryAlias: [String: String] = ["gb": "uk"]

    /// US state full names → our state slugs (CLPlacemark gives full names).
    private static let usStateAlias: [String: String] = [
        "california": "ca", "new york": "ny", "washington": "wa", "texas": "tx",
        "florida": "fl", "illinois": "il", "massachusetts": "ma", "new jersey": "nj",
    ]

    /// Fold an English/romaji place name to a comparison key: lowercase,
    /// diacritic-insensitive (Tōkyō→tokyo), suffix-stripped, no spaces — so a
    /// geocoded prefecture/state lines up with our romaji/pinyin province codes.
    private static func foldPlaceKey(_ raw: String?) -> String {
        guard var t = raw?.lowercased() else { return "" }
        t = t.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        for suffix in [" prefecture", " metropolis", " province", "-to", "-fu", "-ken", "-do",
                       "都", "府", "県", "县", "省", "市"] {
            if t.hasSuffix(suffix) { t = String(t.dropLast(suffix.count)) }
        }
        return t.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Best-effort map a reverse-geocoded placemark to a directory Region.
    /// Pass English-locale fields (`isoCountryCode`, `administrativeArea`,
    /// `locality`). Province codes are romaji/pinyin so they match the
    /// geocoded admin area directly; city falls back to the province's first
    /// entry when the locality can't be matched (the directory is city-coarse).
    static func match(isoCountryCode: String?, adminArea: String?, locality: String?) -> Region? {
        guard let isoRaw = isoCountryCode?.lowercased(), !isoRaw.isEmpty else { return nil }
        let countryCode = isoCountryAlias[isoRaw] ?? isoRaw
        guard let country = country(code: countryCode) else { return nil }

        if country.hasProvinces {
            let adminKey = foldPlaceKey(adminArea)
            let adminLower = (adminArea ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            let provs = provinces(for: countryCode)
            var province = provs.first { foldPlaceKey($0.code) == adminKey }
            if province == nil, let stateCode = usStateAlias[adminLower] {
                province = provs.first { $0.code == stateCode }
            }
            if province == nil {
                province = provs.first { foldPlaceKey($0.name) == adminKey }
            }
            guard let province else { return nil }
            let provCities = cities(country: countryCode, province: province.code)
            let locKey = foldPlaceKey(locality)
            let city = provCities.first { foldPlaceKey($0.code) == locKey || foldPlaceKey($0.name) == locKey }
                ?? provCities.first
            guard let city else { return nil }
            return make(country: countryCode, province: province.code, city: city.code)
        } else {
            let locKey = foldPlaceKey(locality)
            let flatCities = cities(country: countryCode, province: nil)
            if let city = flatCities.first(where: { foldPlaceKey($0.code) == locKey || foldPlaceKey($0.name) == locKey }) {
                return make(country: countryCode, province: nil, city: city.code)
            }
            if let code = defaultRegionCode(forCountry: countryCode) { return resolve(regionCode: code) }
            return nil
        }
    }

    static func localizedCountryName(_ country: Country, language: AppLanguage) -> String {
        guard language != .zh else { return country.name }
        return localizedCountryNames[language]?[country.code] ?? country.name
    }

    static func localizedProvinceName(countryCode: String, province: Province, language: AppLanguage) -> String {
        guard language != .zh else { return province.name }
        return localizedProvinceNames[language]?[countryCode]?[province.code] ?? formattedRegionCode(province.code)
    }

    static func localizedCityName(countryCode: String, provinceCode: String? = nil, city: City, language: AppLanguage) -> String {
        guard language != .zh else { return city.name }
        if let exact = localizedCityNames[language]?[city.code] { return exact }
        return formattedRegionCode(city.code)
    }

    static func localizedShortLabel(_ region: Region, language: AppLanguage) -> String {
        let city = localizedCityName(countryCode: region.countryCode, provinceCode: region.provinceCode, city: City(code: region.cityCode, name: region.cityName), language: language)
        if !region.provinceCode.isEmpty && region.provinceCode != region.cityCode {
            let province = localizedProvinceName(countryCode: region.countryCode, province: Province(code: region.provinceCode, name: region.provinceName), language: language)
            return "\(province) · \(city)"
        }
        return city
    }

    static func localizedHeaderLabel(_ region: Region, language: AppLanguage) -> String {
        "\(region.countryEmoji) \(localizedCityName(countryCode: region.countryCode, provinceCode: region.provinceCode, city: City(code: region.cityCode, name: region.cityName), language: language))"
    }

    static func localizedDisplayName(_ region: Region, language: AppLanguage) -> String {
        let country = localizedCountryNames[language]?[region.countryCode] ?? region.countryName
        let city = localizedCityName(countryCode: region.countryCode, provinceCode: region.provinceCode, city: City(code: region.cityCode, name: region.cityName), language: language)
        if region.provinceName.isEmpty || region.provinceName == region.cityName || region.provinceCode == region.cityCode {
            return "\(country) · \(city)"
        }
        let province = localizedProvinceName(countryCode: region.countryCode, province: Province(code: region.provinceCode, name: region.provinceName), language: language)
        return "\(country) · \(province) · \(city)"
    }

    private static func formattedRegionCode(_ code: String) -> String {
        let special = [
            "sf": "San Francisco", "la": "Los Angeles", "sd": "San Diego", "sj": "San Jose",
            "nyc": "New York", "kl": "Kuala Lumpur", "ca": "California", "ny": "New York",
            "wa": "Washington", "tx": "Texas", "fl": "Florida", "il": "Illinois",
            "ma": "Massachusetts", "nj": "New Jersey",
        ]
        if let value = special[code] { return value }
        return code
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static let localizedCountryNames: [AppLanguage: [String: String]] = [
        .en: [
            "cn": "China", "jp": "Japan", "us": "United States", "sg": "Singapore",
            "kr": "South Korea", "uk": "United Kingdom", "fr": "France", "au": "Australia",
            "ca": "Canada", "th": "Thailand", "my": "Malaysia", "de": "Germany", "nl": "Netherlands",
        ],
        .ja: [
            "cn": "中国", "jp": "日本", "us": "アメリカ", "sg": "シンガポール",
            "kr": "韓国", "uk": "イギリス", "fr": "フランス", "au": "オーストラリア",
            "ca": "カナダ", "th": "タイ", "my": "マレーシア", "de": "ドイツ", "nl": "オランダ",
        ],
    ]

    private static let localizedProvinceNames: [AppLanguage: [String: [String: String]]] = [
        .en: [
            "jp": [
                "tokyo": "Tokyo", "osaka": "Osaka", "kyoto": "Kyoto", "fukuoka": "Fukuoka",
                "aichi": "Aichi", "kanagawa": "Kanagawa", "saitama": "Saitama", "chiba": "Chiba",
                "hyogo": "Hyogo", "hokkaido": "Hokkaido", "miyagi": "Miyagi", "hiroshima": "Hiroshima",
                "okinawa": "Okinawa", "shizuoka": "Shizuoka", "ibaraki": "Ibaraki", "nara": "Nara",
                "mie": "Mie", "kumamoto": "Kumamoto", "kagoshima": "Kagoshima", "nagano": "Nagano",
                "ishikawa": "Ishikawa", "okayama": "Okayama", "niigata": "Niigata", "tochigi": "Tochigi",
                "gunma": "Gunma", "shiga": "Shiga", "gifu": "Gifu",
                "aomori": "Aomori", "iwate": "Iwate", "akita": "Akita", "yamagata": "Yamagata",
                "fukushima": "Fukushima", "toyama": "Toyama", "fukui": "Fukui", "yamanashi": "Yamanashi",
                "wakayama": "Wakayama", "tottori": "Tottori", "shimane": "Shimane", "yamaguchi": "Yamaguchi",
                "tokushima": "Tokushima", "kagawa": "Kagawa", "ehime": "Ehime", "kochi": "Kochi",
                "saga": "Saga", "nagasaki": "Nagasaki", "oita": "Oita", "miyazaki": "Miyazaki",
            ],
            "cn": [:],
        ],
        .ja: [
            "jp": [
                "tokyo": "東京都", "osaka": "大阪府", "kyoto": "京都府", "fukuoka": "福岡県",
                "aichi": "愛知県", "kanagawa": "神奈川県", "saitama": "埼玉県", "chiba": "千葉県",
                "hyogo": "兵庫県", "hokkaido": "北海道", "miyagi": "宮城県", "hiroshima": "広島県",
                "okinawa": "沖縄県", "shizuoka": "静岡県", "ibaraki": "茨城県", "nara": "奈良県",
                "mie": "三重県", "kumamoto": "熊本県", "kagoshima": "鹿児島県", "nagano": "長野県",
                "ishikawa": "石川県", "okayama": "岡山県", "niigata": "新潟県", "tochigi": "栃木県",
                "gunma": "群馬県", "shiga": "滋賀県", "gifu": "岐阜県",
                "aomori": "青森県", "iwate": "岩手県", "akita": "秋田県", "yamagata": "山形県",
                "fukushima": "福島県", "toyama": "富山県", "fukui": "福井県", "yamanashi": "山梨県",
                "wakayama": "和歌山県", "tottori": "鳥取県", "shimane": "島根県", "yamaguchi": "山口県",
                "tokushima": "徳島県", "kagawa": "香川県", "ehime": "愛媛県", "kochi": "高知県",
                "saga": "佐賀県", "nagasaki": "長崎県", "oita": "大分県", "miyazaki": "宮崎県",
            ],
        ],
    ]

    private static let localizedCityNames: [AppLanguage: [String: String]] = [
        .en: [
            "tokyo": "Tokyo", "osaka": "Osaka", "kyoto": "Kyoto", "fukuoka": "Fukuoka",
            "nagoya": "Nagoya", "yokohama": "Yokohama", "kawasaki": "Kawasaki", "saitama": "Saitama",
            "chiba": "Chiba", "kobe": "Kobe", "sapporo": "Sapporo", "sendai": "Sendai",
            "hiroshima": "Hiroshima", "naha": "Naha", "shizuoka": "Shizuoka", "tsukuba": "Tsukuba",
            "nara": "Nara", "yokkaichi": "Yokkaichi", "kumamoto": "Kumamoto", "kagoshima": "Kagoshima",
            "nagano": "Nagano", "kanazawa": "Kanazawa", "okayama": "Okayama", "niigata": "Niigata",
            "utsunomiya": "Utsunomiya", "takasaki": "Takasaki", "otsu": "Otsu", "gifu": "Gifu",
            "hachioji": "Hachioji", "machida": "Machida", "tachikawa": "Tachikawa", "musashino": "Musashino",
            "sakai": "Sakai", "suita": "Suita", "toyonaka": "Toyonaka", "higashiosaka": "Higashiosaka",
            "uji": "Uji", "kitakyushu": "Kitakyushu", "kurume": "Kurume", "toyota": "Toyota",
            "okazaki": "Okazaki", "ichinomiya": "Ichinomiya", "sagamihara": "Sagamihara",
            "kamakura": "Kamakura", "fujisawa": "Fujisawa", "yokosuka": "Yokosuka",
            "kawaguchi": "Kawaguchi", "kawagoe": "Kawagoe", "tokorozawa": "Tokorozawa",
            "koshigaya": "Koshigaya", "funabashi": "Funabashi", "matsudo": "Matsudo",
            "kashiwa": "Kashiwa", "ichikawa": "Ichikawa", "narita": "Narita",
            "nishinomiya": "Nishinomiya", "himeji": "Himeji", "amagasaki": "Amagasaki",
            "asahikawa": "Asahikawa", "hakodate": "Hakodate", "ishinomaki": "Ishinomaki",
            "fukuyama": "Fukuyama", "okinawa": "Okinawa", "hamamatsu": "Hamamatsu",
            "numazu": "Numazu", "mito": "Mito", "hitachinaka": "Hitachinaka",
            "ikoma": "Ikoma", "tsu": "Tsu", "matsumoto": "Matsumoto", "komatsu": "Komatsu",
            "kurashiki": "Kurashiki", "nagaoka": "Nagaoka", "oyama": "Oyama",
            "maebashi": "Maebashi", "kusatsu": "Kusatsu", "ogaki": "Ogaki",
            "aomori": "Aomori", "hachinohe": "Hachinohe", "morioka": "Morioka", "ichinoseki": "Ichinoseki",
            "akita": "Akita", "yamagata": "Yamagata", "tsuruoka": "Tsuruoka", "fukushima": "Fukushima",
            "koriyama": "Koriyama", "iwaki": "Iwaki", "toyama": "Toyama", "takaoka": "Takaoka",
            "fukui": "Fukui", "kofu": "Kofu", "wakayama": "Wakayama", "tottori": "Tottori",
            "yonago": "Yonago", "matsue": "Matsue", "izumo": "Izumo", "yamaguchi": "Yamaguchi",
            "shimonoseki": "Shimonoseki", "tokushima": "Tokushima", "takamatsu": "Takamatsu",
            "matsuyama": "Matsuyama", "imabari": "Imabari", "kochi": "Kochi", "saga": "Saga",
            "nagasaki": "Nagasaki", "sasebo": "Sasebo", "oita": "Oita", "beppu": "Beppu", "miyazaki": "Miyazaki",
            "shanghai": "Shanghai", "beijing": "Beijing", "guangzhou": "Guangzhou", "shenzhen": "Shenzhen",
            "hangzhou": "Hangzhou", "nanjing": "Nanjing", "suzhou": "Suzhou", "chengdu": "Chengdu",
            "hongkong": "Hong Kong", "singapore": "Singapore", "seoul": "Seoul", "busan": "Busan",
            "london": "London", "manchester": "Manchester", "toronto": "Toronto", "vancouver": "Vancouver",
            "sydney": "Sydney", "melbourne": "Melbourne", "paris": "Paris", "berlin": "Berlin",
        ],
        .ja: [
            "tokyo": "東京", "osaka": "大阪", "kyoto": "京都", "fukuoka": "福岡",
            "nagoya": "名古屋", "yokohama": "横浜", "kawasaki": "川崎", "saitama": "さいたま",
            "chiba": "千葉", "kobe": "神戸", "sapporo": "札幌", "sendai": "仙台",
            "hiroshima": "広島", "naha": "那覇", "shizuoka": "静岡", "tsukuba": "つくば",
            "nara": "奈良", "yokkaichi": "四日市", "kumamoto": "熊本", "kagoshima": "鹿児島",
            "nagano": "長野", "kanazawa": "金沢", "okayama": "岡山", "niigata": "新潟",
            "utsunomiya": "宇都宮", "takasaki": "高崎", "otsu": "大津", "gifu": "岐阜",
            "hachioji": "八王子", "machida": "町田", "tachikawa": "立川", "musashino": "武蔵野",
            "sakai": "堺", "suita": "吹田", "toyonaka": "豊中", "higashiosaka": "東大阪",
            "uji": "宇治", "kitakyushu": "北九州", "kurume": "久留米", "toyota": "豊田",
            "okazaki": "岡崎", "ichinomiya": "一宮", "sagamihara": "相模原", "kamakura": "鎌倉",
            "fujisawa": "藤沢", "yokosuka": "横須賀", "kawaguchi": "川口", "kawagoe": "川越",
            "tokorozawa": "所沢", "koshigaya": "越谷", "funabashi": "船橋", "matsudo": "松戸",
            "kashiwa": "柏", "ichikawa": "市川", "narita": "成田", "nishinomiya": "西宮",
            "himeji": "姫路", "amagasaki": "尼崎", "asahikawa": "旭川", "hakodate": "函館",
            "ishinomaki": "石巻", "fukuyama": "福山", "okinawa": "沖縄", "hamamatsu": "浜松",
            "numazu": "沼津", "mito": "水戸", "hitachinaka": "ひたちなか", "ikoma": "生駒",
            "tsu": "津", "matsumoto": "松本", "komatsu": "小松", "kurashiki": "倉敷",
            "nagaoka": "長岡", "oyama": "小山", "maebashi": "前橋", "kusatsu": "草津", "ogaki": "大垣",
            "aomori": "青森", "hachinohe": "八戸", "morioka": "盛岡", "ichinoseki": "一関",
            "akita": "秋田", "yamagata": "山形", "tsuruoka": "鶴岡", "fukushima": "福島",
            "koriyama": "郡山", "iwaki": "いわき", "toyama": "富山", "takaoka": "高岡",
            "fukui": "福井", "kofu": "甲府", "wakayama": "和歌山", "tottori": "鳥取",
            "yonago": "米子", "matsue": "松江", "izumo": "出雲", "yamaguchi": "山口",
            "shimonoseki": "下関", "tokushima": "徳島", "takamatsu": "高松",
            "matsuyama": "松山", "imabari": "今治", "kochi": "高知", "saga": "佐賀",
            "nagasaki": "長崎", "sasebo": "佐世保", "oita": "大分", "beppu": "別府", "miyazaki": "宮崎",
            "shanghai": "上海", "beijing": "北京", "guangzhou": "広州", "shenzhen": "深圳",
            "hongkong": "香港", "singapore": "シンガポール", "seoul": "ソウル", "busan": "釜山",
            "london": "ロンドン", "toronto": "トロント", "vancouver": "バンクーバー",
            "sydney": "シドニー", "melbourne": "メルボルン", "paris": "パリ", "berlin": "ベルリン",
        ],
    ]

    static var popular: [Region] {
        popularRegionCodes.compactMap { resolve(regionCode: $0) }
    }
}
