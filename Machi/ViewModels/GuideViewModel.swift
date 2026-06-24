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
    @Published private(set) var guideOS: KaiXGuideActivePlanResponse?
    @Published private(set) var isGuideOSLoading = false
    @Published private(set) var guideOSMessage: String?
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

    func loadGuideOS(force: Bool = false) async {
        guard KaiXBackend.token != nil else {
            guideOS = nil
            guideOSMessage = nil
            return
        }
        if !force, guideOS != nil { return }
        isGuideOSLoading = true
        guideOSMessage = nil
        defer { isGuideOSLoading = false }
        do {
            guideOS = try await KaiXAPIClient.shared.guideActivePlan(language: currentGuideLanguage())
        } catch {
            guideOSMessage = "个人计划暂时无法同步，稍后下拉刷新即可恢复。"
        }
    }

    @discardableResult
    func completeGuideTodo(_ todo: KaiXGuideTodoDTO) async -> Bool {
        guard KaiXBackend.token != nil else {
            GuestGate.shared.requireLogin("登录后可以同步 Guide 计划、Todo 和提醒。")
            return false
        }
        do {
            _ = try await KaiXAPIClient.shared.completeGuideTodo(id: todo.id)
            await loadGuideOS(force: true)
            return true
        } catch {
            guideOSMessage = "任务完成状态没有保存成功，请稍后再试。"
            return false
        }
    }

    @discardableResult
    func createQuickTodo(content: String, plannedDate: String? = nil) async -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard KaiXBackend.token != nil else {
            GuestGate.shared.requireLogin("登录后可以保存 Todo、日历和提醒。")
            return false
        }
        isGuideOSLoading = true
        guideOSMessage = nil
        defer { isGuideOSLoading = false }
        do {
            _ = try await KaiXAPIClient.shared.createGuideTodo(.init(
                content: text,
                todoType: "manual",
                plannedDate: plannedDate
            ))
            await loadGuideOS(force: true)
            return true
        } catch {
            guideOSMessage = "Todo 添加失败，请稍后再试。"
            return false
        }
    }

    @discardableResult
    func startPlan(journeyKey: String, planType: String = "guide") async -> Bool {
        guard KaiXBackend.token != nil else {
            GuestGate.shared.requireLogin("登录后可以把指南生成可执行计划。")
            return false
        }
        do {
            _ = try await KaiXAPIClient.shared.startGuidePlan(journeyKey: journeyKey, planType: planType)
            await loadGuideOS(force: true)
            return true
        } catch {
            guideOSMessage = "计划生成失败，请稍后再试。"
            return false
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
        let normalizedCountry = country.isEmpty ? "jp" : country
        // Prefer the unified search endpoint so iOS and Web search the same set
        // (articles + schools + companies + products + faq + journeys). Fall
        // back to the legacy per-type queries + offline article match if it's
        // unavailable, so an older backend or a dropped connection still works.
        do {
            let response = try await KaiXAPIClient.shared.guideSearch(country: normalizedCountry, language: currentGuideLanguage(), keyword: q)
            searchResults = response.groups.articles ?? []
            schoolResults = response.groups.schools ?? []
            companyResults = response.groups.companies ?? []
        } catch {
            await legacySearch(country: normalizedCountry, q: q)
        }
    }

    private func legacySearch(country: String, q: String) async {
        // Schools + companies are best-effort after the article query: a
        // failure there must never blank the article results.
        do {
            let response = try await KaiXAPIClient.shared.guideArticles(country: country, language: currentGuideLanguage(), keyword: q, pageSize: 20)
            searchResults = response.items
        } catch {
            let fallbackArticles = GuideFallbackContent.articles(language: currentGuideLanguage())
            searchResults = fallbackArticles.filter { article in
                ([article.title, article.summary, article.categoryKey, article.subCategoryKey] + article.tags)
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(q)
            }
            errorMessage = searchResults.isEmpty ? "搜索暂时无法连接服务器，换个关键词或下拉刷新试试。" : "搜索暂时无法连接服务器，先显示内置指南结果。"
        }
        let schoolsResponse = try? await KaiXAPIClient.shared.guideSchools(country: country, keyword: q, pageSize: 8)
        let companiesResponse = try? await KaiXAPIClient.shared.guideCompanies(country: country, keyword: q, pageSize: 8)
        schoolResults = schoolsResponse?.items ?? []
        companyResults = companiesResponse?.items ?? []
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
            journeys: journeys,
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

    // Offline journey headers so the action-path grid still renders without a
    // network. Steps load when online (journey detail is network-only).
    private static func journey(_ key: String, _ title: String, _ subtitle: String, icon: String, color: String, days: Int, order: Int) -> KaiXGuideJourneyDTO {
        .init(id: "fallback-journey-\(key)", key: key, country: "jp", language: "zh-CN",
              title: title, subtitle: subtitle, audience: "", icon: icon, color: color,
              heroTitle: title, heroSubtitle: subtitle, estimatedDays: days, sortOrder: order,
              status: "published", stepCount: nil)
    }

    static let journeys: [KaiXGuideJourneyDTO] = [
        journey("arrival", "刚到日本 7 天", "落地后最关键的一周，把手续一次办顺", icon: "arrival", color: "#0EA5E9", days: 7, order: 1),
        journey("prepare", "准备来日本", "出发前把目的、预算和材料理清楚", icon: "plan", color: "#6366F1", days: 60, order: 2),
        journey("housing", "租房 / 搬家", "看懂初期费用，避开外国人租房的坑", icon: "home", color: "#F97316", days: 30, order: 3),
        journey("language_school", "语言学校 / 留学", "择校、费用、签证与升学衔接", icon: "plane", color: "#EC4899", days: 120, order: 4),
        journey("grad_school", "大学院 / 升学", "研究计划书、联系教授到出愿面试", icon: "graduation", color: "#14B8A6", days: 240, order: 5),
        journey("job_hunting", "日本就职", "从自我分析到内定与签证变更", icon: "briefcase", color: "#147067", days: 180, order: 6),
        journey("jlpt", "JLPT / EJU 备考", "定级、周期、教材、模考到报名", icon: "language", color: "#0EA5E9", days: 90, order: 7),
        journey("visa", "签证 / 手续", "在留更新、变更与打工限制", icon: "document", color: "#6366F1", days: 30, order: 8),
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
            language: "zh-CN",
            sortOrder: order,
            articleCount: nil,
            productCount: nil,
            seoTitle: nil,
            seoDescription: nil,
            isActive: true,
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
            saved: nil,
            progressPercent: nil,
            readingProgress: nil,
            publishedAt: nil,
            updatedAt: nil
        )
    }
}
