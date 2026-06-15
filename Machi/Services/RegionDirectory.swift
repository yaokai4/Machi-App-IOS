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
                return "\(cityName) · \(provinceName)"
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
        "tokyo":    [.init(code: "tokyo", name: "东京")],
        "osaka":    [.init(code: "osaka", name: "大阪")],
        "kyoto":    [.init(code: "kyoto", name: "京都")],
        "fukuoka":  [.init(code: "fukuoka", name: "福冈")],
        "aichi":    [.init(code: "nagoya", name: "名古屋")],
        "kanagawa": [.init(code: "yokohama", name: "横滨"), .init(code: "kawasaki", name: "川崎")],
        "saitama":  [.init(code: "saitama", name: "埼玉")],
        "chiba":    [.init(code: "chiba", name: "千叶")],
        "hyogo":    [.init(code: "kobe", name: "神户")],
        "hokkaido": [.init(code: "sapporo", name: "札幌")],
        "miyagi":   [.init(code: "sendai", name: "仙台")],
        "hiroshima":[.init(code: "hiroshima", name: "广岛")],
        "okinawa":  [.init(code: "naha", name: "那霸")],
        "shizuoka": [.init(code: "shizuoka", name: "静冈")],
        "ibaraki":  [.init(code: "tsukuba", name: "筑波")],
        "nara":     [.init(code: "nara", name: "奈良")],
        "mie":      [.init(code: "yokkaichi", name: "四日市")],
        "kumamoto": [.init(code: "kumamoto", name: "熊本")],
        "kagoshima":[.init(code: "kagoshima", name: "鹿儿岛")],
        "nagano":   [.init(code: "nagano", name: "长野")],
        "ishikawa": [.init(code: "kanazawa", name: "金泽")],
        "okayama":  [.init(code: "okayama", name: "冈山")],
        "niigata":  [.init(code: "niigata", name: "新潟")],
        "tochigi":  [.init(code: "utsunomiya", name: "宇都宫")],
        "gunma":    [.init(code: "takasaki", name: "高崎")],
        "shiga":    [.init(code: "otsu", name: "大津")],
        "gifu":     [.init(code: "gifu", name: "岐阜")],
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
        "jp.saitama.saitama", "jp.chiba.chiba",
        "jp.hyogo.kobe", "jp.hokkaido.sapporo",
        "jp.miyagi.sendai", "jp.hiroshima.hiroshima",
        "jp.okinawa.naha", "jp.shizuoka.shizuoka",
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
        .init(code: "kanto", name: "关东圈", provinceCodes: ["tokyo", "kanagawa", "saitama", "chiba", "ibaraki", "tochigi", "gunma"]),
        .init(code: "kansai", name: "关西圈", provinceCodes: ["osaka", "kyoto", "hyogo", "nara", "shiga", "mie"]),
        .init(code: "nagoya", name: "名古屋·中部", provinceCodes: ["aichi", "gifu", "shizuoka", "nagano", "niigata", "ishikawa"]),
        .init(code: "fukuoka", name: "福冈·九州", provinceCodes: ["fukuoka", "kumamoto", "kagoshima"]),
        .init(code: "sapporo", name: "札幌·北海道", provinceCodes: ["hokkaido"]),
        .init(code: "sendai", name: "仙台·东北", provinceCodes: ["miyagi"]),
        .init(code: "other", name: "其他城市", provinceCodes: ["hiroshima", "okayama", "okinawa"]),
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
            return "\(city) · \(province)"
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
