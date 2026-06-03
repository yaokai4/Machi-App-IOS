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
        .init(code: "uk", name: "英国",     emoji: "🇬🇧", tier: 2, hasProvinces: false),
        .init(code: "ca", name: "加拿大",   emoji: "🇨🇦", tier: 2, hasProvinces: false),
        .init(code: "au", name: "澳大利亚", emoji: "🇦🇺", tier: 2, hasProvinces: false),
        .init(code: "sg", name: "新加坡",   emoji: "🇸🇬", tier: 2, hasProvinces: false),
        .init(code: "kr", name: "韩国",     emoji: "🇰🇷", tier: 2, hasProvinces: false),
        .init(code: "th", name: "泰国",     emoji: "🇹🇭", tier: 3, hasProvinces: false),
        .init(code: "my", name: "马来西亚", emoji: "🇲🇾", tier: 3, hasProvinces: false),
        .init(code: "de", name: "德国",     emoji: "🇩🇪", tier: 3, hasProvinces: false),
        .init(code: "fr", name: "法国",     emoji: "🇫🇷", tier: 3, hasProvinces: false),
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
        "uk":      [.init(code: "london", name: "伦敦"), .init(code: "manchester", name: "曼彻斯特"),
                    .init(code: "edinburgh", name: "爱丁堡")],
        "ca_flat": [.init(code: "toronto", name: "多伦多"), .init(code: "vancouver", name: "温哥华"), .init(code: "montreal", name: "蒙特利尔")],
        "au":      [.init(code: "sydney", name: "悉尼"), .init(code: "melbourne", name: "墨尔本"),
                    .init(code: "brisbane", name: "布里斯班"), .init(code: "perth", name: "珀斯")],
        "sg":      [.init(code: "singapore", name: "新加坡")],
        "kr":      [.init(code: "seoul", name: "首尔"), .init(code: "busan", name: "釜山")],
        "th":      [.init(code: "bangkok", name: "曼谷"), .init(code: "chiangmai", name: "清迈"),
                    .init(code: "phuket", name: "普吉")],
        "my":      [.init(code: "kl", name: "吉隆坡"), .init(code: "penang", name: "槟城")],
        "de":      [.init(code: "berlin", name: "柏林"), .init(code: "munich", name: "慕尼黑"),
                    .init(code: "hamburg", name: "汉堡")],
        "fr":      [.init(code: "paris", name: "巴黎"), .init(code: "lyon", name: "里昂")],
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
        // Other Asia / SEA
        "sg.singapore", "kr.seoul",
        "th.bangkok",
    ]

    // MARK: - Lookups

    static func country(code: String) -> Country? {
        countries.first { $0.code == code.lowercased() }
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

    static var popular: [Region] {
        popularRegionCodes.compactMap { resolve(regionCode: $0) }
    }
}
