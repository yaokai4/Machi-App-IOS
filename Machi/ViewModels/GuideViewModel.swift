import Foundation
import Combine

@MainActor
final class GuideViewModel: ObservableObject {
    @Published private(set) var home: KaiXGuideHomeResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var searchResults: [KaiXGuideArticleDTO] = []
    // Universal Guide search also surfaces matching schools + companies, not
    // just articles — the hero search box is the single entry into everything.
    @Published private(set) var schoolResults: [KaiXGuideSchoolDTO] = []
    @Published private(set) var companyResults: [KaiXGuideCompanyDTO] = []
    @Published private(set) var isSearching = false
    @Published var searchText = ""

    var hasAnySearchResult: Bool {
        !searchResults.isEmpty || !schoolResults.isEmpty || !companyResults.isEmpty
    }

    private var loadedCountry = ""
    private var loadedLanguage = ""

    var isComingSoon: Bool {
        home?.status == "coming_soon"
    }

    func load(country: String, force: Bool = false) async {
        let normalizedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let language = currentGuideLanguage()
        if !force, loadedCountry == normalizedCountry, loadedLanguage == language, home != nil { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            home = try await KaiXAPIClient.shared.guideHome(country: normalizedCountry.isEmpty ? "jp" : normalizedCountry, language: language)
            loadedCountry = normalizedCountry
            loadedLanguage = language
        } catch {
            if normalizedCountry.isEmpty || normalizedCountry == "jp" {
                home = GuideFallbackContent.home(language: language)
                loadedCountry = normalizedCountry
                loadedLanguage = language
                errorMessage = "网络暂时不可用，已载入内置日本指南。联网后下拉即可刷新最新内容。"
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func search(country: String, keyword: String? = nil) async {
        let q = (keyword ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        // Schools + companies are best-effort and run concurrently with the
        // article query: a failure there must never blank the article results.
        let normalizedCountry = country.isEmpty ? "jp" : country
        async let schoolsResp = KaiXAPIClient.shared.guideSchools(country: normalizedCountry, keyword: q, pageSize: 8)
        async let companiesResp = KaiXAPIClient.shared.guideCompanies(country: normalizedCountry, keyword: q, pageSize: 8)
        do {
            let response = try await KaiXAPIClient.shared.guideArticles(country: country, language: currentGuideLanguage(), keyword: q, pageSize: 20)
            searchResults = response.items
        } catch {
            let fallbackArticles = GuideFallbackContent.articles(language: currentGuideLanguage())
            searchResults = fallbackArticles.filter { article in
                let haystack = ([article.title, article.summary, article.categoryKey, article.subCategoryKey] + article.tags)
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(q)
                return haystack
            }
            errorMessage = searchResults.isEmpty ? "搜索暂时无法连接服务器，换个关键词或下拉刷新试试。" : "搜索暂时无法连接服务器，先显示内置指南结果。"
        }
        schoolResults = (try? await schoolsResp)?.items ?? []
        companyResults = (try? await companiesResp)?.items ?? []
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
        schoolResults = []
        companyResults = []
    }

    private func currentGuideLanguage() -> String {
        let appLanguage = AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? "")
        switch appLanguage {
        case .ja:
            return "ja"
        case .en:
            return "en"
        case .zh, .system:
            return "zh-CN"
        }
    }
}

private enum GuideFallbackContent {
    static func home(language: String) -> KaiXGuideHomeResponse {
        KaiXGuideHomeResponse(
            status: "published",
            country: "jp",
            language: language,
            hero: .init(
                title: "日本生活与成长指南",
                subtitle: "升学、就职、签证、租房、手续与日语备考，一屏进入关键路径。",
                note: "内置精选内容可离线浏览；联网后会同步后台最新文章、学校库、公司库和服务。",
                searchPlaceholder: "搜索签证、租房、JLPT、履历书、银行卡...",
                quickTags: ["租房", "签证更新", "JLPT", "履历书", "银行卡", "搬家"]
            ),
            emptyState: nil,
            categories: categories,
            goals: .init(title: "你现在想先解决什么？", entries: goals),
            goalEntries: goals,
            resourceEntries: resources,
            featuredArticles: articles(language: language),
            featuredProducts: [],
            featuredServices: [],
            featuredSchools: [],
            companyHighlights: [],
            latestArticles: articles(language: language).suffix(3).map { $0 },
            faq: faq,
            reviewDisclaimer: "离线指南只用于快速了解流程，正式申请请以官方页面和后台审核资料为准。",
            schoolDisclaimer: "学校信息联网后会以官方来源与后台审核数据为准。",
            companyDisclaimer: "公司信息联网后会展示招聘页、签证支持和真实评价。"
        )
    }

    static func articles(language: String) -> [KaiXGuideArticleDTO] {
        [
            article(
                id: "fallback-visa",
                title: "在日签证与在留卡：到期前 90 天检查清单",
                slug: "fallback-japan-visa-checklist",
                summary: "整理更新在留资格、地址变更、资格外活动许可和常见材料缺口，适合刚到日本或准备续签的人。",
                category: "life_japan",
                subCategory: "visa",
                tags: ["签证", "在留卡", "役所"],
                language: language
            ),
            article(
                id: "fallback-rent",
                title: "东京租房避坑：初期费用、保证公司和退房清洁",
                slug: "fallback-tokyo-rent-guide",
                summary: "看懂礼金、敷金、保证料、火灾保险、退去精算和外国人租房常见审查点。",
                category: "life_japan",
                subCategory: "housing",
                tags: ["租房", "东京", "初期费用"],
                language: language
            ),
            article(
                id: "fallback-career",
                title: "日本就职第一步：履历书、职务经歴书和面试节奏",
                slug: "fallback-japan-career-first-step",
                summary: "从自我分析到応募、面试、内定和签证支持，快速理解外国人在日本求职的主线。",
                category: "career_japan",
                subCategory: "job_hunting",
                tags: ["就职", "履历书", "面试"],
                language: language
            ),
            article(
                id: "fallback-jlpt",
                title: "JLPT 备考节奏：N2/N1 三个月冲刺安排",
                slug: "fallback-jlpt-plan",
                summary: "把词汇、文法、读解、听解拆成每周任务，并说明错题复盘和模拟题频率。",
                category: "jlpt",
                subCategory: "study_plan",
                tags: ["JLPT", "N2", "N1"],
                language: language
            )
        ]
    }

    private static let categories: [KaiXGuideCategoryDTO] = [
        category("life_japan", title: "在日生活", subtitle: "役所、租房、银行卡、手机、医疗", icon: "home", color: "#0EA5E9", order: 1),
        category("career_japan", title: "日本就职", subtitle: "就活、履历书、面试、签证支持", icon: "briefcase", color: "#14B8A6", order: 2),
        category("study_japan", title: "日本升学", subtitle: "大学院、研究计划书、出愿", icon: "graduation", color: "#6366F1", order: 3),
        category("study_abroad_japan", title: "语言学校", subtitle: "择校、费用、入境与打工", icon: "plane", color: "#F97316", order: 4),
        category("jlpt", title: "日语考级", subtitle: "JLPT、EJU、学习计划", icon: "language", color: "#EC4899", order: 5)
    ]

    private static let resources: [KaiXGuideResourceEntryDTO] = [
        .init(key: "japan_schools", title: "日本学校库", description: "联网后查看大学、大学院、专门学校和语言学校的官方招生资料。", icon: "school", href: "/guide/schools"),
        .init(key: "foreigner_friendly_companies", title: "就职公司库", description: "联网后查看外国人友好公司、签证支持、岗位来源和真实评价。", icon: "company", href: "/guide/companies")
    ]

    private static let goals: [KaiXGuideGoalEntryDTO] = [
        .init(targetKey: "settle", title: "刚到日本，先把手续办顺", categoryKey: "life_japan", subCategoryKey: "arrival"),
        .init(targetKey: "rent", title: "准备租房或搬家", categoryKey: "life_japan", subCategoryKey: "housing"),
        .init(targetKey: "career", title: "开始日本就职", categoryKey: "career_japan", subCategoryKey: "job_hunting"),
        .init(targetKey: "jlpt", title: "准备 JLPT", categoryKey: "jlpt", subCategoryKey: "study_plan")
    ]

    private static let faq: [KaiXGuideFaqDTO] = [
        .init(id: "fallback-faq-1", question: "为什么没有联网也能看到指南？", answer: "Machi 内置了高频日本生活与成长路径，避免网络不稳时指南页变成空白。联网后会优先显示后台最新内容。", categoryKey: "life_japan"),
        .init(id: "fallback-faq-2", question: "学校库和公司库数据以哪里为准？", answer: "正式数据会以官方来源、后台审核和用户反馈为准；离线内容只作为入口和流程提示。", categoryKey: "study_japan")
    ]

    private static func category(_ key: String, title: String, subtitle: String, icon: String, color: String, order: Int) -> KaiXGuideCategoryDTO {
        .init(
            id: "fallback-\(key)",
            key: key,
            parentKey: "",
            title: title,
            subtitle: subtitle,
            description: subtitle,
            icon: icon,
            color: color,
            country: "jp",
            sortOrder: order,
            subCategories: []
        )
    }

    private static func article(
        id: String,
        title: String,
        slug: String,
        summary: String,
        category: String,
        subCategory: String,
        tags: [String],
        language: String
    ) -> KaiXGuideArticleDTO {
        .init(
            id: id,
            title: title,
            slug: slug,
            summary: summary,
            body: nil,
            categoryKey: category,
            subCategoryKey: subCategory,
            contentType: "guide",
            country: "jp",
            city: "",
            language: language,
            coverImage: "",
            tags: tags,
            authorType: "editorial",
            authorName: "Machi Guide",
            isFeatured: true,
            isFree: true,
            isPaid: false,
            status: "published",
            viewCount: 0,
            saveCount: 0,
            publishedAt: nil,
            updatedAt: nil
        )
    }
}
