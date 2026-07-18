import Foundation

// Split out of KaiXAPIDTO.swift for maintainability (Machi Guide · journeys · Guide OS).
// Plain Codable mirrors of the backend JSON; see KaiXAPIDTO.swift for the
// shared conventions (snake_case fields, Decodable-only, no SwiftData here).

// MARK: - Machi Guide / 日本指南

struct KaiXGuideHeroDTO: Codable, Equatable {
    let title: String
    let subtitle: String
    let note: String
    let searchPlaceholder: String
    let quickTags: [String]
}

struct KaiXGuideEmptyStateDTO: Codable, Equatable {
    let title: String
    let body: String
    let action: String
    let actionCountry: String
}

struct KaiXGuideCategoryDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let key: String
    let parentKey: String
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let color: String
    let country: String
    let language: String?
    let sortOrder: Int
    let articleCount: Int?
    let productCount: Int?
    let seoTitle: String?
    let seoDescription: String?
    let isActive: Bool?
    let subCategories: [KaiXGuideCategoryDTO]?
}

struct KaiXGuideGoalEntryDTO: Codable, Equatable, Identifiable {
    let targetKey: String
    let title: String
    let categoryKey: String
    let subCategoryKey: String
    var id: String { targetKey }
}

struct KaiXGuideResourceEntryDTO: Codable, Equatable, Identifiable, Hashable {
    let key: String
    let title: String
    let description: String
    let icon: String
    let href: String
    var id: String { key }
}

struct KaiXGuideGoalsDTO: Codable, Equatable {
    let title: String
    let entries: [KaiXGuideGoalEntryDTO]
}

struct KaiXGuideArticleDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String
    let summary: String
    let body: String?
    let categoryKey: String
    let subCategoryKey: String
    let contentType: String
    let country: String
    let city: String
    let language: String
    let coverImage: String
    let tags: [String]
    let authorType: String
    let authorName: String
    let isFeatured: Bool
    let isFree: Bool
    let isPaid: Bool
    let status: String
    let viewCount: Int
    let saveCount: Int
    let saved: Bool?
    let progressPercent: Int?
    let readingProgress: KaiXGuideArticleProgressDTO?
    let publishedAt: String?
    let updatedAt: String?
    // G3: article provenance / freshness — kept in sync with the web client and
    // the server serializer (sourceUrl/sourceLabel/verifiedAt/staleAfterDays).
    // Optional so older API responses still decode AND local editorial
    // placeholders can omit them.
    let sourceUrl: String?
    let sourceLabel: String?
    let verifiedAt: String?
    let staleAfterDays: Int?
}

struct KaiXGuideArticleProgressDTO: Codable, Equatable, Hashable {
    let progressPercent: Int
    let completedAt: String?
    let lastReadAt: String?
}

struct KaiXGuideArticleProgressResponse: Codable {
    let status: String
    let articleId: String
    let slug: String
    let progress: KaiXGuideArticleProgressDTO
}

struct KaiXGuideProductDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String
    let subtitle: String
    let description: String
    let categoryKey: String
    let subCategoryKey: String
    let productType: String
    let price: Int
    let currency: String
    let priceLabel: String
    let originalPrice: Int?
    let discountLabel: String?
    let memberPriceLabel: String?
    let isPriceHidden: Bool?
    let isAppointmentOnly: Bool?
    let billingType: String?
    let billingPeriod: String?
    let servicePriceType: String?
    let startingPrice: Int?
    let memberDiscountPercent: Int?
    let serviceDurationMinutes: Int?
    let depositRequired: Bool?
    let depositAmount: Int?
    let cancellationPolicy: String?
    let canView: Bool?
    let canPurchase: Bool?
    let ctaLabel: String?
    let coverImage: String
    let tags: [String]
    let targetAudience: String
    let deliveryMethod: String
    let country: String
    let language: String
    let isDigital: Bool
    let isService: Bool
    let isFree: Bool
    let isPaid: Bool
    let isComingSoon: Bool
    let status: String
    let purchaseCount: Int
    let rating: Double
    // BE4 review aggregate. `ratingCount` = published review count; `ratingSummary`
    // carries avg + count (+ optional 5-bucket distribution on the detail endpoint).
    // Both optional so older payloads / list responses still decode.
    let ratingCount: Int?
    let ratingSummary: KaiXGuideRatingSummaryDTO?
    let publishedAt: String?
    let fileCount: Int?
    // Member / payment / gating fields from the unified Guide API. All optional so
    // older payloads still decode. `purchaseContent`/`fileUrl` appear only for an
    // entitled viewer (owned order or active member). iOS shows digital purchases as
    // 即将开放 (no external Stripe button) until Apple IAP is wired.
    let previewContent: String?
    let hasPurchaseContent: Bool?
    let hasFile: Bool?
    let isMemberIncluded: Bool?
    let isMemberDiscount: Bool?
    let memberPrice: Int?
    let memberEffectivePrice: Int?
    let isFeatured: Bool?
    let refundPolicy: String?
    let notes: String?
    let sortOrder: Int?
    let iosIapProductId: String?
    let appleProductId: String?
    let stripeAvailable: Bool?
    let purchaseContent: String?
    let fileUrl: String?
    let access: KaiXGuideProductAccess?
    // Machi Points purchasing (prices server-side only).
    let walletEligible: Bool?
    let walletPricePoints: Int?
    let memberWalletPricePoints: Int?
    let pointsPriceLabel: String?
    let memberPointsPriceLabel: String?
    let canBuyWithPoints: Bool?
    let fulfillmentType: String?
    let entitlementType: String?
    let platformPolicy: String?
    let pointsContext: KaiXWalletPointsContextDTO?
    // 契约 C-1:服务端键名精确为 deliverable_ready(数字商品文件未就绪 → false)。
    // 旧 payload 缺省视为 true,购买 CTA 不受影响。
    let deliverable_ready: Bool?

    /// C-1 就绪判定的调用侧口径:缺省(旧后端)一律视为就绪。
    var deliverableReady: Bool { deliverable_ready ?? true }
}

struct KaiXGuideProductAccess: Codable, Equatable, Hashable {
    let owned: Bool?
    let memberUnlocked: Bool?
    let canAccess: Bool?
    let signedIn: Bool?
}

struct KaiXGuideCompanyScoresDTO: Codable, Equatable, Hashable {
    let foreignerFriendly: Double
    let visaSupport: Double?
    let interviewDifficulty: Double
    let overtime: Double
    let salaryBenefit: Double
    let workLifeBalance: Double
    let careerGrowth: Double?
}

struct KaiXGuideCompanyDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let corporateNumber: String?
    let companyName: String
    let companyNameJp: String
    let companyNameEn: String?
    let slug: String
    let industry: String
    let subIndustry: String?
    let country: String
    let prefecture: String?
    let city: String
    let ward: String?
    let address: String?
    let postalCode: String?
    let latitude: Double?
    let longitude: Double?
    let website: String
    let careerUrl: String?
    let newGraduateUrl: String?
    let midCareerUrl: String?
    let globalCareerUrl: String?
    let size: String
    let companySize: String?
    let foundedYear: Int
    let description: String
    let shortDescription: String?
    let isForeignerFriendly: Bool?
    let acceptsForeignApplicants: Bool?
    let supportsWorkVisa: Bool?
    let supportsNewGraduate: Bool?
    let supportsMidCareer: Bool?
    let hasEnglishPositions: Bool?
    let hasGlobalRoles: Bool?
    let hasForeignEmployees: Bool?
    let requiredJapaneseLevel: String?
    let requiredEnglishLevel: String?
    let employmentTypes: [String]?
    let averageSalaryMin: Int?
    let averageSalaryMax: Int?
    let currency: String?
    let scores: KaiXGuideCompanyScoresDTO?
    let reviewCount: Int
    let interviewReviewCount: Int?
    let saveCount: Int?
    let sourceType: String?
    let sourceName: String?
    let sourceUrl: String?
    let sourceLastCheckedAt: String?
    let verificationStatus: String?
    let dataQualityScore: Int?
    let isFeatured: Bool?
    let status: String
}

struct KaiXGuideSchoolDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let slug: String
    let schoolName: String
    let schoolNameJp: String
    let schoolNameEn: String
    let schoolType: String
    let country: String
    let prefecture: String
    let city: String
    let ward: String?
    let address: String?
    let postalCode: String?
    let latitude: Double?
    let longitude: Double?
    let website: String
    let admissionUrl: String?
    let internationalAdmissionUrl: String
    let applicationUrl: String?
    let scholarshipUrl: String?
    let careerSupportUrl: String?
    let languageSupportUrl: String?
    let dormitoryUrl: String?
    let description: String
    let shortDescription: String
    let isAcceptingInternationalStudents: Bool?
    let hasEnglishProgram: Bool?
    let hasJapaneseProgram: Bool?
    let hasScholarship: Bool?
    let hasDormitory: Bool?
    let hasCareerSupport: Bool?
    let hasLanguageSupport: Bool?
    let tuitionMin: Int
    let tuitionMax: Int
    let currency: String
    let applicationPeriods: [String]?
    let admissionMonths: [String]
    let requiredJapaneseLevel: String
    let requiredEnglishLevel: String
    let ejuRequired: String?
    let jlptRequired: String?
    let toeflRequired: String?
    let ieltsRequired: String?
    let fieldsOfStudy: [String]
    let departments: [String]?
    let faculties: [String]?
    let graduateSchools: [String]?
    let tags: [String]?
    let sourceType: String?
    let sourceName: String?
    let sourceUrl: String
    let sourceLastCheckedAt: String?
    let verificationStatus: String
    let dataQualityScore: Int?
    let isFeatured: Bool
    let viewCount: Int?
    let saveCount: Int
    let savedByMe: Bool?
    let status: String
}

struct KaiXGuideSchoolProgramDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let schoolId: String
    let programName: String
    let programNameJp: String
    let programNameEn: String
    let degreeLevel: String
    let programType: String
    let field: String
    let subField: String?
    let facultyName: String?
    let departmentName: String?
    let graduateSchoolName: String?
    let languageOfInstruction: String
    let durationMonths: Int
    let admissionMonths: [String]
    let applicationPeriod: String
    let tuition: Int
    let currency: String
    let description: String
    let applicationUrl: String
    let sourceUrl: String?
    let verificationStatus: String?
    let status: String
}

struct KaiXGuideSchoolAdmissionDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let schoolId: String
    let programId: String
    let admissionType: String
    let enrollmentMonth: String
    let requiredDocuments: [String]
    let selectionMethod: String
    let scholarshipInfo: String
    let notes: String
    let sourceUrl: String
    let verificationStatus: String?
    let status: String
}

struct KaiXGuideCompanyPositionDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let companyId: String
    let positionTitle: String
    let positionTitleJp: String
    let positionCategory: String
    let employmentType: String
    let city: String
    let remoteType: String
    let salaryMin: Int
    let salaryMax: Int
    let currency: String
    let requiredJapaneseLevel: String
    let requiredEnglishLevel: String
    let visaSupport: String
    let description: String
    let requirements: String
    let sourceUrl: String
    let verificationStatus: String?
    let status: String
}

struct KaiXGuideCompanyReviewDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let companyId: String
    let anonymous: Bool
    let position: String
    let employmentType: String
    let pros: String
    let cons: String
    let overtimeLevel: String
    let foreignerSupport: String
    let salaryBenefits: String
    let careerGrowth: String
    let recommendationScore: Double
    let createdAt: String
}

struct KaiXGuideInterviewReviewDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let companyId: String
    let companyName: String?
    let companySlug: String?
    let anonymous: Bool
    let position: String
    let employmentType: String
    let interviewRounds: Int
    let interviewLanguage: String
    let difficulty: String
    let questions: String
    let processDescription: String
    let result: String
    let interviewYear: Int
    let city: String
    let createdAt: String
}

struct KaiXGuideFaqDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let question: String
    let answer: String
    let categoryKey: String
}

// MARK: - Guide Journeys (situation -> ordered action path)

struct KaiXGuideJourneyDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let key: String
    let country: String?
    let language: String?
    let title: String
    let subtitle: String
    let audience: String
    let icon: String
    let color: String
    let heroTitle: String
    let heroSubtitle: String
    let estimatedDays: Int
    let sortOrder: Int
    let status: String
    let stepCount: Int?
}

struct KaiXGuideJourneyStepDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let journeyKey: String
    let stepKey: String
    let title: String
    let summary: String
    let body: String?
    let actionLabel: String
    let actionType: String
    let actionTarget: String
    let categoryKey: String
    let articleSlugs: [String]
    let productSlugs: [String]
    let required: Bool
    let estimatedMinutes: Int
    let deadlineHint: String
    let sortOrder: Int
    let status: String
    let relatedArticles: [KaiXGuideArticleDTO]?
    let relatedProducts: [KaiXGuideProductDTO]?
}

struct KaiXGuideJourneysResponse: Codable {
    let status: String
    let country: String
    let language: String?
    let journeys: [KaiXGuideJourneyDTO]
}

/// Per-step progress as returned inside a journey detail's `progress` map.
struct KaiXGuideStepProgressState: Codable, Equatable, Hashable {
    let status: String
    let completedAt: String?
    let plannedDate: String?
    let dueAt: String?
    let priority: String?
    let notifyEnabled: Bool?
    let calendarNote: String?
}

struct KaiXGuideJourneyDetailResponse: Codable {
    let status: String
    let country: String
    let language: String?
    let journey: KaiXGuideJourneyDTO
    let steps: [KaiXGuideJourneyStepDTO]
    let progress: [String: KaiXGuideStepProgressState]?
    let disclaimer: String?
}

struct KaiXGuideProgressDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let journeyKey: String
    let stepKey: String
    let status: String
    let completedAt: String?
    let reminderAt: String?
    let plannedDate: String?
    let dueAt: String?
    let priority: String?
    let notifyEnabled: Bool?
    let calendarNote: String?
    let notes: String?
    let updatedAt: String?
}

struct KaiXGuideProgressSummaryDTO: Codable, Equatable, Hashable {
    let journeyKey: String
    let done: Int
    let total: Int
    let percent: Int
}

struct KaiXGuideProgressResponse: Codable {
    let status: String
    let items: [KaiXGuideProgressDTO]
    let summary: [KaiXGuideProgressSummaryDTO]
}

struct KaiXGuideProgressUpdatePayload: Encodable {
    var journeyKey: String
    var stepKey: String
    var status: String
    var reminderAt: String?
    var plannedDate: String?
    var dueAt: String?
    var priority: String?
    var notifyEnabled: Bool?
    var calendarNote: String?
    var notes: String?
}

// MARK: - Guide OS (server-first plans / todos / calendar)

struct KaiXGuideProfileDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let userId: String
    let identityType: String
    let country: String
    let city: String
    let isInJapan: Bool
    /// 来日阶段 pre_arrival / just_arrived / first_year / long_term ("" = 未设置)。
    /// Optional so decoding stays compatible with servers that predate the field.
    let arrivalStage: String?
    let visaStatus: String
    let visaExpiresAt: String?
    let japaneseLevel: String
    let targetJapaneseLevel: String
    let targetLevel: String
    let graduationDate: String?
    let targetEntryTerm: String
    let targetIndustry: String
    let targetSchoolType: String
    let weeklyAvailableMinutes: Int
    let needsMaterials: Bool
    let needsServices: Bool
    let createdAt: String?
    let updatedAt: String?
}

struct KaiXGuideTodoDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let userId: String
    let planId: String
    let sourceType: String
    let sourceId: String
    let journeyKey: String
    let stepKey: String
    let title: String
    let summary: String
    let todoType: String
    let status: String
    let priority: String
    let plannedDate: String?
    let dueAt: String?
    let reminderAt: String?
    let completedAt: String?
    let estimatedMinutes: Int
    let notes: String
    let recurrence: String?
    let listName: String?
    let tags: [String]?
    let relatedArticleSlugs: [String]
    let relatedProductSlugs: [String]
    let relatedServiceSlugs: [String]
    let createdAt: String?
    let updatedAt: String?
    var steps: [KaiXGuideTodoStep]? = nil

    var isDone: Bool { status == "done" }
    var displayDate: String? { plannedDate ?? dueAt ?? reminderAt }
    /// "daily" / "weekly" / "" — a recurring study habit vs a one-off task.
    /// 该文案会被 View 层直接拼进三语模板(如 r+"循环" / r+"繰り返し" /
    /// r+" repeat"),必须随 App 语言返回,否则英/日界面出现"每日 repeat"
    /// 中外混排。DTO 拿不到 @Environment,按仓库既有模式(GuideOSViewModel
    /// / PostRepository)从 UserDefaults 解析当前语言。
    var recurrenceLabel: String? {
        let language = AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? "")
        switch recurrence {
        case "daily":
            switch language {
            case .ja: return "毎日"
            case .en: return "Daily"
            default: return "每日"
            }
        case "weekly":
            switch language {
            case .ja: return "毎週"
            case .en: return "Weekly"
            default: return "每周"
            }
        case "monthly":
            switch language {
            case .ja: return "毎月"
            case .en: return "Monthly"
            default: return "每月"
            }
        default: return nil
        }
    }
}

struct KaiXGuidePlanDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let userId: String
    let planType: String
    let title: String
    let subtitle: String
    let status: String
    let targetDate: String?
    let startedAt: String?
    let progressPercent: Int
    let currentTodoId: String
    let sourceJourneyKey: String
    let todoTotal: Int?
    let todoDone: Int?
    let nextTodo: KaiXGuideTodoDTO?
    let createdAt: String?
    let updatedAt: String?
}

struct KaiXGuideCalendarItemDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let todoId: String
    let title: String
    let date: String?
    let startAt: String?
    let endAt: String?
    let type: String
    let status: String
    let planId: String
    let notes: String?
    let recurrence: String?
    let reminderAt: String?
    let allDay: Bool?
    let todo: KaiXGuideTodoDTO?
}

struct KaiXGuideApplicationDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let userId: String
    let planId: String
    let type: String
    let careerTrack: String?
    let name: String
    let department: String
    let position: String
    let deadline: String?
    let interviewAt: String?
    let resultAt: String?
    let status: String
    let stage: String?
    let websiteUrl: String?
    let interviewLocation: String?
    let meetingUrl: String?
    let contactName: String?
    let contactEmail: String?
    let priority: String?
    let favorite: Bool?
    let tags: [String]?
    let archivedAt: String?
    let stages: [KaiXGuideApplicationStage]?
    let notes: String
    let createdAt: String?
    let updatedAt: String?
}

struct KaiXGuideApplicationStage: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let applicationId: String
    let stage: String
    let note: String
    let occurredAt: String?
    let createdAt: String?
}

struct KaiXGuideTransactionDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let kind: String
    let amount: Int
    let currency: String
    let category: String
    let account: String?
    let occurredOn: String?
    let note: String
    let source: String?
    var isIncome: Bool { kind == "income" }
}

struct KaiXGuideFinanceCategoryDTO: Codable, Equatable, Identifiable, Hashable {
    var id: String { code }
    let code: String
    let zh: String
    let ja: String
    let en: String
    let icon: String
}

struct KaiXGuideBudgetDTO: Codable, Equatable, Hashable {
    let category: String
    let monthlyLimit: Int
    let currency: String?
}

struct KaiXGuideFinanceSummaryDTO: Codable, Equatable {
    struct CategoryAmount: Codable, Equatable, Hashable { let category: String; let amount: Int }
    struct BudgetProgress: Codable, Equatable, Hashable { let category: String; let limit: Int; let spent: Int }
    let month: String
    let currency: String
    let income: Int
    let expense: Int
    let net: Int
    let byCategory: [CategoryAmount]
    let budgets: [BudgetProgress]
    let fixedMonthly: Int
    let lastMonthExpense: Int
    // O3: the server's single ledger currency + the count of this month's entries
    // in OTHER currencies that were not summed into the totals.
    let ledgerCurrency: String?
    let otherCurrencyCount: Int?
}

struct KaiXGuideTransactionPayload: Encodable {
    var kind: String
    var amount: Int
    var category: String
    var occurredOn: String?
    var note: String?
    var currency: String?
}

struct KaiXGuideTransactionsResponse: Decodable {
    let items: [KaiXGuideTransactionDTO]
    let total: Int?
}

struct KaiXGuideTransactionResponse: Decodable {
    let transaction: KaiXGuideTransactionDTO
}

struct KaiXGuideFinanceCategoriesResponse: Decodable {
    let expense: [KaiXGuideFinanceCategoryDTO]
    let income: [KaiXGuideFinanceCategoryDTO]
}

struct KaiXGuideBudgetsResponse: Decodable {
    let items: [KaiXGuideBudgetDTO]
}

struct KaiXGuideBudgetSetPayload: Encodable {
    let category: String
    let monthlyLimit: Int
}

struct KaiXGuideFinanceTrendPoint: Codable, Equatable, Hashable, Identifiable {
    var id: String { month }
    let month: String
    let income: Int
    let expense: Int
    let net: Int
}

struct KaiXGuideFinanceTrendResponse: Decodable {
    let months: [KaiXGuideFinanceTrendPoint]
}

struct KaiXGuidePostFixedResponse: Decodable {
    let posted: Int
}

struct KaiXGuidePostFixedPayload: Encodable {
    let month: String?
}

struct KaiXGuideDigestDTO: Decodable {
    struct Finance: Decodable { let income: Int; let expense: Int; let net: Int; let fixedMonthly: Int; let hasData: Bool }
    struct Bill: Decodable, Identifiable, Hashable { let id: String; let title: String; let amount: Int; let dueOn: String?; let daysLeft: Int }
    struct Window: Decodable, Identifiable, Hashable { let id: String; let title: String; let daysLeft: Int; let open: Bool; let monthlyCost: Int }
    struct DocExpiry: Decodable, Identifiable, Hashable { let id: String; let title: String; let expiresOn: String?; let daysLeft: Int }
    struct BudgetAlert: Decodable, Identifiable, Hashable { var id: String { category }; let category: String; let limit: Int; let spent: Int; let over: Bool }
    let month: String
    let finance: Finance
    let upcomingBills: [Bill]
    let contractWindows: [Window]
    let documentExpiries: [DocExpiry]
    let budgetAlerts: [BudgetAlert]
    let openTodos: Int
    let hasSetup: Bool
}

struct KaiXGuideQuickSetupResponse: Decodable { let created: Int; let profile: String }
struct KaiXGuideQuickSetupPayload: Encodable { let profile: String }

struct KaiXGuideLifeItemDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let userId: String
    let type: String
    let title: String
    let provider: String
    let amount: Int
    let currency: String
    let paymentMethod: String
    let dueDay: Int
    let dueAt: String?
    let recurrence: String
    let reminderDaysBefore: Int
    let notes: String
    let active: Bool
    let createdAt: String?
    let updatedAt: String?
}

struct KaiXGuideLifePaymentDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let lifeItemId: String
    let amount: Int
    let currency: String
    let paymentMethod: String
    let paidAt: String
    let notes: String
    let createdAt: String?
}

struct KaiXGuideContractDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let userId: String
    let category: String
    let title: String
    let provider: String
    let startDate: String?
    let endDate: String?
    let cancellationWindowStart: String?
    let cancellationWindowEnd: String?
    let autoRenew: Bool
    let monthlyCost: Int
    let yearlyCost: Int
    let currency: String
    let reminderDaysBefore: Int
    let contactInfo: String
    let notes: String
    let status: String
    let createdAt: String?
    let updatedAt: String?
}

struct KaiXGuideDocumentDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let userId: String
    let category: String
    let title: String
    let expiresAt: String?
    let reminderDaysBefore: Int
    let notes: String
    let status: String
    let createdAt: String?
    let updatedAt: String?
}

struct KaiXGuideProfileResponse: Codable {
    let status: String
    let profile: KaiXGuideProfileDTO?
    let generatedTodoCount: Int?
}

struct KaiXGuidePlanListResponse: Codable {
    let status: String
    let items: [KaiXGuidePlanDTO]
}

struct KaiXGuidePlanResponse: Codable {
    let status: String
    let plan: KaiXGuidePlanDTO?
}

struct KaiXGuidePlanStartResponse: Codable {
    let status: String
    let plan: KaiXGuidePlanDTO?
    let todos: [KaiXGuideTodoDTO]
}

struct KaiXGuideTodoListResponse: Codable {
    let status: String
    let items: [KaiXGuideTodoDTO]
    let total: Int
}

struct KaiXGuideTodoResponse: Codable {
    let status: String
    let todo: KaiXGuideTodoDTO?
}

struct KaiXGuideCalendarResponse: Codable {
    let status: String
    let items: [KaiXGuideCalendarItemDTO]
    let total: Int
}

struct KaiXGuideCalendarEventResponse: Codable {
    let status: String
    let event: KaiXGuideCalendarItemDTO?
}

struct KaiXGuideActivePlanResponse: Codable {
    let status: String
    let profile: KaiXGuideProfileDTO?
    let plan: KaiXGuidePlanDTO?
    let todayTodos: [KaiXGuideTodoDTO]
    let upcomingTodos: [KaiXGuideTodoDTO]
    let openTodos: [KaiXGuideTodoDTO]
    let recommendedProducts: [KaiXGuideProductDTO]?
    let recommendedServices: [KaiXGuideProductDTO]?
    // Identity-driven personalization (spec P0.1). Optional so older backends
    // keep decoding.
    let identityType: String?
    let suggestedJourneys: [KaiXGuideSuggestedJourney]?
    let defaultJourneyKey: String?
    let recommendedNextActions: [KaiXGuideNextAction]?
    // Retention signals (spec P1).
    let retention: KaiXGuideRetention?
}

struct KaiXGuideRetention: Codable, Equatable, Hashable {
    let weekDone: Int
    let streakDays: Int
}

struct KaiXGuideLifePreset: Codable, Equatable, Identifiable, Hashable {
    let type: String
    let label: String
    let icon: String
    let recurrence: String
    let reminderDaysBefore: Int
    let kind: String
    var id: String { type }
}

struct KaiXGuideLifePresetsResponse: Codable {
    let status: String
    let items: [KaiXGuideLifePreset]
}

struct KaiXGuideSuggestedJourney: Codable, Equatable, Identifiable, Hashable {
    let key: String
    let title: String
    let subtitle: String
    let icon: String
    let color: String
    var id: String { key }
}

struct KaiXGuideNextAction: Codable, Equatable, Identifiable, Hashable {
    let kind: String
    let title: String
    let subtitle: String?
    let todoId: String?
    let todoType: String?
    let journeyKey: String?
    let dueAt: String?
    var id: String { "\(kind)-\(journeyKey ?? todoId ?? title)" }
}

struct KaiXGuideStudyPlanResponse: Codable {
    let status: String
    let plan: KaiXGuidePlanDTO?
    let todos: [KaiXGuideTodoDTO]
}

struct KaiXGuideApplicationResponse: Codable {
    let status: String
    let application: KaiXGuideApplicationDTO?
}

struct KaiXGuideApplicationsResponse: Codable {
    let status: String
    let items: [KaiXGuideApplicationDTO]
    let total: Int
}

struct KaiXGuideLifeItemResponse: Codable {
    let status: String
    let item: KaiXGuideLifeItemDTO?
}

struct KaiXGuideLifeItemsResponse: Codable {
    let status: String
    let items: [KaiXGuideLifeItemDTO]
    let total: Int
}

struct KaiXGuideLifePaymentsResponse: Codable {
    let status: String
    let items: [KaiXGuideLifePaymentDTO]
    let total: Int
}

struct KaiXGuideLifePaymentResponse: Codable {
    let status: String
    let payment: KaiXGuideLifePaymentDTO
    let item: KaiXGuideLifeItemDTO
    let nextDueAt: String?
}

struct KaiXGuideContractResponse: Codable {
    let status: String
    let contract: KaiXGuideContractDTO?
}

struct KaiXGuideContractsResponse: Codable {
    let status: String
    let items: [KaiXGuideContractDTO]
    let total: Int
}

struct KaiXGuideDocumentResponse: Codable {
    let status: String
    let document: KaiXGuideDocumentDTO?
}

struct KaiXGuideDocumentsResponse: Codable {
    let status: String
    let items: [KaiXGuideDocumentDTO]
    let total: Int
}

struct KaiXGuideAttachmentsResponse: Codable {
    let status: String
    let items: [KaiXUploadedFileDTO]
    let total: Int
}

struct KaiXUploadPrivateViewURLResponse: Codable {
    struct Payload: Codable {
        let url: String
        let expiresIn: Int?
    }
    let ok: Bool?
    let data: Payload?
    let url: String?
    let expiresIn: Int?

    var resolvedURL: String {
        data?.url ?? url ?? ""
    }
}

struct KaiXGuideRecommendationsResponse: Codable {
    let status: String
    let materials: [KaiXGuideProductDTO]
    let services: [KaiXGuideProductDTO]
    let products: [KaiXGuideProductDTO]
}

struct KaiXGuideProfileUpdatePayload: Encodable {
    var identityType: String? = nil
    var city: String? = nil
    var isInJapan: Bool? = nil
    var arrivalStage: String? = nil
    var visaStatus: String? = nil
    var visaExpiresAt: String? = nil
    var japaneseLevel: String? = nil
    var targetJapaneseLevel: String? = nil
    var graduationDate: String? = nil
    var targetEntryTerm: String? = nil
    var targetIndustry: String? = nil
    var targetSchoolType: String? = nil
    var weeklyAvailableMinutes: Int? = nil
    var needsMaterials: Bool? = nil
    var needsServices: Bool? = nil
}

struct KaiXGuideTodoStep: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var text: String
    var done: Bool
}

struct KaiXGuideTodoUpdatePayload: Encodable {
    var title: String? = nil
    var summary: String? = nil
    var status: String? = nil
    var priority: String? = nil
    var notes: String? = nil
    var plannedDate: String? = nil
    var dueAt: String? = nil
    var reminderAt: String? = nil
    var steps: [KaiXGuideTodoStep]? = nil
    var recurrence: String? = nil
    var listName: String? = nil
    var tags: [String]? = nil
}

struct KaiXGuideTodoCreatePayload: Encodable {
    var content: String
    var title: String? = nil
    var summary: String? = nil
    var todoType: String? = nil
    var priority: String? = nil
    var plannedDate: String? = nil
    var dueAt: String? = nil
    var reminderAt: String? = nil
    var planId: String? = nil
    var notes: String? = nil
    var recurrence: String? = nil
    var listName: String? = nil
    var tags: [String]? = nil
}

struct KaiXGuideCalendarEventPayload: Encodable {
    var title: String? = nil
    var date: String? = nil
    var startAt: String? = nil
    var endAt: String? = nil
    var type: String? = nil
    var status: String? = nil
    var planId: String? = nil
    var notes: String? = nil
    var recurrence: String? = nil
    var reminderAt: String? = nil
    var allDay: Bool? = nil
}

struct KaiXGuideApplicationPayload: Encodable {
    var planId: String?
    var type: String
    var name: String
    var department: String?
    var position: String?
    var deadline: String?
    var interviewAt: String?
    var resultAt: String?
    var notes: String?
    /// "shinsotsu" (新卒) | "tenshoku" (社会人转职) — picks the company milestone
    /// ladder; ignored for school. (spec iOS sync)
    var careerTrack: String?
    var stage: String?
    var stageNote: String?
    var websiteUrl: String?
    var interviewLocation: String?
    var meetingUrl: String?
    var contactName: String?
    var contactEmail: String?
    var priority: String?
    var favorite: Bool?
    var tags: [String]?
    var status: String?
}

struct KaiXGuideLifeItemPayload: Encodable {
    var type: String
    var title: String
    var provider: String?
    var amount: Int?
    var currency: String?
    var paymentMethod: String?
    var autoDebit: Bool?
    var dueDay: Int?
    var dueAt: String?
    var recurrence: String?
    var reminderDaysBefore: Int?
    var notes: String?
}

struct KaiXGuideLifePaymentPayload: Encodable {
    var amount: Int
    var currency: String
    var paymentMethod: String?
    var paidAt: String
    var notes: String?
}

struct KaiXGuideContractPayload: Encodable {
    var category: String
    var title: String
    var provider: String?
    var startDate: String?
    var endDate: String?
    var cancellationWindowStart: String?
    var cancellationWindowEnd: String?
    var autoRenew: Bool?
    var monthlyCost: Int?
    var yearlyCost: Int?
    var currency: String?
    var reminderDaysBefore: Int?
    var contactInfo: String?
    var notes: String?
    var status: String?
}

struct KaiXGuideDocumentPayload: Encodable {
    var category: String
    var title: String
    var expiresAt: String?
    var reminderDaysBefore: Int?
    var notes: String?
    var status: String?
}

struct KaiXGuideSearchScope: Codable, Equatable, Identifiable, Hashable {
    let key: String
    let label: String
    var id: String { key }
}

struct KaiXGuideSearchGroups: Codable, Equatable {
    let articles: [KaiXGuideArticleDTO]?
    let schools: [KaiXGuideSchoolDTO]?
    let companies: [KaiXGuideCompanyDTO]?
    let products: [KaiXGuideProductDTO]?
    let faq: [KaiXGuideFaqDTO]?
    let journeys: [KaiXGuideJourneyDTO]?
}

struct KaiXGuideSearchResponse: Codable {
    let status: String
    let query: String
    let scopes: [KaiXGuideSearchScope]
    let groups: KaiXGuideSearchGroups
}

struct KaiXGuideSavedItemDTO: Codable, Equatable, Identifiable, Hashable {
    let itemId: String
    let itemType: String
    let createdAt: String?
    var id: String { "\(itemType):\(itemId)" }
}

struct KaiXGuideSavedResponse: Codable {
    let status: String
    let items: [KaiXGuideSavedItemDTO]
}

struct KaiXGuideHomeResponse: Codable {
    let status: String
    let country: String
    let language: String?
    let hero: KaiXGuideHeroDTO
    let emptyState: KaiXGuideEmptyStateDTO?
    let categories: [KaiXGuideCategoryDTO]
    let goals: KaiXGuideGoalsDTO?
    let goalEntries: [KaiXGuideGoalEntryDTO]
    // Additive (Stage 1 backend): situation -> action-path entries. Optional so
    // older cached payloads and offline fallback still decode.
    let journeys: [KaiXGuideJourneyDTO]?
    let resourceEntries: [KaiXGuideResourceEntryDTO]?
    let featuredArticles: [KaiXGuideArticleDTO]
    let featuredProducts: [KaiXGuideProductDTO]
    let featuredServices: [KaiXGuideProductDTO]
    let featuredSchools: [KaiXGuideSchoolDTO]?
    let companyHighlights: [KaiXGuideCompanyDTO]
    let latestArticles: [KaiXGuideArticleDTO]
    let faq: [KaiXGuideFaqDTO]
    let reviewDisclaimer: String?
    let schoolDisclaimer: String?
    let companyDisclaimer: String?
}

struct KaiXGuideCategoriesResponse: Codable {
    let status: String
    let country: String
    let categories: [KaiXGuideCategoryDTO]
    let emptyState: KaiXGuideEmptyStateDTO?
}

struct KaiXGuideListResponse<Item: Codable>: Codable {
    let status: String
    let country: String
    let items: [Item]
    let page: Int
    let pageSize: Int
    let total: Int
    let emptyState: KaiXGuideEmptyStateDTO?
    let disclaimer: String?
    let membershipActive: Bool?
}

struct KaiXGuideArticleDetailResponse: Codable {
    let status: String
    let article: KaiXGuideArticleDTO
    let related: [KaiXGuideArticleDTO]
}

struct KaiXGuideProductDetailResponse: Codable {
    let status: String
    let product: KaiXGuideProductDTO
}

// MARK: - Guide product reviews (BE4 / guide_reviews)

/// One star bucket of the rating distribution, e.g. { star: 5, count: 12 }.
struct KaiXGuideRatingBucketDTO: Codable, Equatable, Hashable, Identifiable {
    let star: Int
    let count: Int
    var id: Int { star }
}

/// Rating aggregate over published reviews. On lists this carries just avg +
/// count; the reviews endpoint additionally fills the 5-bucket `distribution`.
struct KaiXGuideRatingSummaryDTO: Codable, Equatable, Hashable {
    let ratingAvg: Double
    let ratingCount: Int
    let distribution: [KaiXGuideRatingBucketDTO]?

    /// Buckets padded to all five stars (5→1) so the bar chart always renders a
    /// full ladder even when the server omits empty buckets.
    var fullDistribution: [KaiXGuideRatingBucketDTO] {
        let existing = Dictionary(uniqueKeysWithValues: (distribution ?? []).map { ($0.star, $0.count) })
        return [5, 4, 3, 2, 1].map { KaiXGuideRatingBucketDTO(star: $0, count: existing[$0] ?? 0) }
    }
}

/// Light author summary attached to non-anonymous reviews. Anonymous reviews
/// carry `author == nil` — the server is the sole authority on that gate.
struct KaiXGuideReviewAuthorDTO: Codable, Equatable, Hashable {
    let id: String?
    let handle: String?
    let displayName: String?
    let avatarUrl: String?
}

/// A product review. `status` is pending/published/rejected/hidden/withdrawn;
/// only `published` ones appear in the public list. `isMine` drives the
/// edit/withdraw affordance; `viewerVoted` the "有帮助" toggle state.
struct KaiXGuideReviewDTO: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let productId: String?
    let rating: Int
    let body: String
    let status: String
    let helpfulCount: Int
    let reportCount: Int?
    let anonymous: Bool
    let createdAt: String?
    let updatedAt: String?
    let isMine: Bool
    let viewerVoted: Bool
    let author: KaiXGuideReviewAuthorDTO?
}

/// Public paginated reviews list + rating distribution summary.
struct KaiXGuideReviewsResponse: Codable {
    let status: String
    let productId: String
    let summary: KaiXGuideRatingSummaryDTO
    let items: [KaiXGuideReviewDTO]
    let hasMore: Bool
}

/// The caller's own review of a product (any status) + whether they may write one.
struct KaiXGuideReviewMeResponse: Codable {
    let status: String
    let productId: String
    let canReview: Bool
    let review: KaiXGuideReviewDTO?
}

/// Result of submitting a review — status is "pending_review" (App Store 1.2:
/// reviews are never shown before an admin approves).
struct KaiXGuideReviewSubmitResponse: Codable {
    let status: String
    let id: String?
    let message: String?
}

/// Result of a helpful-vote toggle.
struct KaiXGuideReviewHelpfulResponse: Codable {
    let status: String
    let id: String
    let helpfulCount: Int
    let viewerVoted: Bool
}

struct KaiXGuideCompanyDetailResponse: Codable {
    let status: String
    let company: KaiXGuideCompanyDTO
    let interviewReviewCount: Int
    let workReviewCount: Int
    let positions: [KaiXGuideCompanyPositionDTO]?
    let relatedArticles: [KaiXGuideArticleDTO]?
    let disclaimer: String
}

struct KaiXGuideSchoolDetailResponse: Codable {
    let status: String
    let school: KaiXGuideSchoolDTO
    let programs: [KaiXGuideSchoolProgramDTO]
    let admissions: [KaiXGuideSchoolAdmissionDTO]
    let relatedArticles: [KaiXGuideArticleDTO]
    let relatedProducts: [KaiXGuideProductDTO]
    let disclaimer: String
}

struct KaiXGuideCompanyReviewsResponse: Codable {
    let status: String
    let companyId: String
    let workReviews: [KaiXGuideCompanyReviewDTO]
    let interviewReviews: [KaiXGuideInterviewReviewDTO]
    let disclaimer: String
}

struct KaiXGuideSubmitResponse: Codable {
    let status: String
    let id: String?
    let message: String
    let orderId: String?
}

struct KaiXGuideCompanyReviewPayload: Encodable {
    let companyId: String
    let position: String
    let employmentType: String
    let pros: String
    let cons: String
    let overtimeLevel: String
    let foreignerSupport: String
    let salaryBenefits: String
    let careerGrowth: String
    let recommendationScore: Double
    let anonymous: Bool
}

struct KaiXGuideInterviewReviewPayload: Encodable {
    let companyId: String
    let position: String
    let employmentType: String
    let interviewRounds: Int
    let interviewLanguage: String
    let difficulty: String
    let questions: String
    let processDescription: String
    let result: String
    let interviewYear: Int
    let city: String
    let anonymous: Bool
}

struct KaiXGuideServiceRequestPayload: Encodable {
    let productId: String
    let serviceType: String
    let contactMethod: String
    let message: String
}

struct KaiXPageDTO<Item: Codable>: Codable {
    let items: [Item]
    let next_cursor: String?

    init(items: [Item], next_cursor: String?) {
        self.items = items
        self.next_cursor = next_cursor
    }

    enum CodingKeys: String, CodingKey { case items, next_cursor }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // items 逐条容错:单条坏数据只丢该条,不让个人主页(帖子/回复分页)整屏报错。
        items = try container.decode(KaiXLossyDecodableArray<Item>.self, forKey: .items).elements
        next_cursor = try container.decodeIfPresent(String.self, forKey: .next_cursor)
    }
}

struct KaiXLoginResponse: Codable {
    let token: String
    let user: KaiXUserDTO
}

struct KaiXGoogleAuthStartResponse: Codable {
    let authorization_url: String
    let url: String?
    let state: String
    let expires_in: Int
}

struct KaiXAvailabilityResponse: Codable, Equatable {
    let available: Bool
    let message: String
    let code: String?
}

struct KaiXEmailCodeResponse: Codable, Equatable {
    let ok: Bool
    let challenge_id: String?
    let email_hint: String?
    let expires_in: Int
}

/// Image-captcha challenge gating the anonymous auth endpoints. When the
/// server has enforcement off for the requested scene, `enabled` is false
/// and the UI hides the captcha row entirely.
struct KaiXCaptchaResponse: Codable, Equatable {
    let enabled: Bool
    let captcha_id: String?
    /// `data:image/png;base64,…`
    let image: String?
    let expires_in: Int?

    var pngData: Data? {
        guard let image, let comma = image.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(image[image.index(after: comma)...]))
    }
}

struct KaiXVerifyCodeResponse: Codable, Equatable {
    let ok: Bool?
    let success: Bool?
    let message: String?
}

/// 逐条容错的数组解码:单条脏数据(缺字段/类型漂移的一帖)只丢弃该条,
/// 绝不让整页解码失败——否则服务端混进一条坏帖就是整屏 feed 报错。
struct KaiXLossyDecodableArray<Element: Codable>: Codable {
    let elements: [Element]

    /// 空壳 Decodable:解码必然成功且不读取内容,专门用来"消费"解码失败的
    /// 那一条——unkeyedContainer 解码失败不会推进 currentIndex,不消费会死循环。
    private struct AnyDecodableSkip: Codable {
        init() {}
        init(from decoder: Decoder) throws {}
        func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encodeNil() }
    }

    init(_ elements: [Element]) { self.elements = elements }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        if let count = container.count { result.reserveCapacity(count) }
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                result.append(value)
            } else {
                _ = try? container.decode(AnyDecodableSkip.self)
            }
        }
        elements = result
    }

    func encode(to encoder: Encoder) throws {
        try elements.encode(to: encoder)
    }
}

struct KaiXFeedResponse: Codable {
    let items: [KaiXPostDTO]
    let next_cursor: String?
    let mode: String

    init(items: [KaiXPostDTO], next_cursor: String?, mode: String) {
        self.items = items
        self.next_cursor = next_cursor
        self.mode = mode
    }

    enum CodingKeys: String, CodingKey { case items, next_cursor, mode }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // items 逐条容错:一条坏帖只丢该条,不让整页 feed 变成错误页。
        items = try container.decode(KaiXLossyDecodableArray<KaiXPostDTO>.self, forKey: .items).elements
        next_cursor = try container.decodeIfPresent(String.self, forKey: .next_cursor)
        mode = try container.decode(String.self, forKey: .mode)
    }
}

struct KaiXTrendingResponse: Codable {
    let posts: [KaiXPostDTO]
    let topics: [KaiXTopicDTO]
    let users: [KaiXUserDTO]

    enum CodingKeys: String, CodingKey { case posts, topics, users }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // posts 逐条容错:单条坏帖只丢该条,不让整个热榜变错误页(与主 feed 一致)。
        posts = try container.decode(KaiXLossyDecodableArray<KaiXPostDTO>.self, forKey: .posts).elements
        topics = try container.decode([KaiXTopicDTO].self, forKey: .topics)
        users = try container.decode([KaiXUserDTO].self, forKey: .users)
    }
}

struct KaiXExplorePostsResponse: Codable {
    let items: [KaiXPostDTO]?
    let posts: [KaiXPostDTO]?
    let days: Int?
    let fallbackUsed: Bool?

    var orderedPosts: [KaiXPostDTO] { items ?? posts ?? [] }

    enum CodingKeys: String, CodingKey { case items, posts, days, fallbackUsed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // items/posts 逐条容错:单条坏帖只丢该条,不让发现页(happening/hot)整屏报错。
        items = try container.decodeIfPresent(KaiXLossyDecodableArray<KaiXPostDTO>.self, forKey: .items)?.elements
        posts = try container.decodeIfPresent(KaiXLossyDecodableArray<KaiXPostDTO>.self, forKey: .posts)?.elements
        days = try container.decodeIfPresent(Int.self, forKey: .days)
        fallbackUsed = try container.decodeIfPresent(Bool.self, forKey: .fallbackUsed)
    }
}

struct KaiXExploreTopicsResponse: Codable {
    let topics: [KaiXTopicDTO]?
    let items: [KaiXTopicDTO]?
    let days: Int?
    let fallbackUsed: Bool?

    var orderedTopics: [KaiXTopicDTO] { topics ?? items ?? [] }
}

// N8: lightweight reputation surface (consumes /api/reputation/me).
struct KaiXReputationProfileDTO: Codable, Equatable {
    let level: Int?
    let levelName: String?
    let levelNameEn: String?
    let levelNameJa: String?
    let reputationLabel: String?
    let publicTrustLabel: String?
    let xp: Int?
    let nextLevelXp: Int?
    let xpToNext: Int?

    enum CodingKeys: String, CodingKey {
        case level
        case levelName
        case levelNameEn = "level_name_en"
        case levelNameJa = "level_name_ja"
        case reputationLabel
        case publicTrustLabel = "public_trust_label"
        case xp
        case nextLevelXp
        case xpToNext = "xp_to_next"
    }
}

/// One tier of the reputation ladder (GET /api/reputation/levels) — used by the
/// profile reputation sheet to show the full level pathway + per-level perks.
struct KaiXReputationLevelDTO: Decodable, Identifiable, Equatable {
    let level: Int
    let xpRequired: Int
    let nameZh: String?
    let nameEn: String?
    let nameJa: String?
    let descriptionZh: String?
    let descriptionEn: String?
    let descriptionJa: String?
    let privileges: [String]?

    var id: Int { level }

    enum CodingKeys: String, CodingKey {
        case level
        case xpRequired = "xp_required"
        case nameZh = "name_zh"
        case nameEn = "name_en"
        case nameJa = "name_ja"
        case descriptionZh = "description_zh"
        case descriptionEn = "description_en"
        case descriptionJa = "description_ja"
        case privileges
    }
}

struct KaiXSavedSearchDTO: Codable, Identifiable, Equatable {
    let id: String
    let vertical: String?
    let keyword: String?
    let category: String?
    let label: String?
    let cadence: String?
    let citySlug: String?
    let matchCount: Int?
}

struct KaiXSearchResponse: Codable {
    let posts: [KaiXPostDTO]
    let users: [KaiXUserDTO]
    let topics: [KaiXTopicDTO]
    // O7: cross-city listing hits when called with kind=listing. Optional so
    // responses that omit it (older/posts-only) still decode.
    let listings: [KaiXCityListingDTO]?

    enum CodingKeys: String, CodingKey { case posts, users, topics, listings }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // posts 逐条容错:单条坏帖只丢该条,不让搜索结果页整屏报错(与主 feed 一致)。
        posts = try container.decode(KaiXLossyDecodableArray<KaiXPostDTO>.self, forKey: .posts).elements
        users = try container.decode([KaiXUserDTO].self, forKey: .users)
        topics = try container.decode([KaiXTopicDTO].self, forKey: .topics)
        listings = try container.decodeIfPresent([KaiXCityListingDTO].self, forKey: .listings)
    }
}

struct KaiXNotificationsResponse: Codable {
    let items: [KaiXNotificationDTO]
    let unread_count: Int
}

struct KaiXMessagesResponse: Codable {
    let items: [KaiXMessageDTO]
    /// 服务端历史分页信号(配合 before_id 游标);旧服务端不下发时为 nil,
    /// 调用方可退化为 items.count == limit 的启发式判断。
    let has_more: Bool?

    init(items: [KaiXMessageDTO], has_more: Bool? = nil) {
        self.items = items
        self.has_more = has_more
    }
}

struct KaiXBootstrapResponse: Codable {
    let user: KaiXUserDTO
    let feed: [KaiXPostDTO]
    let unread_notifications: Int
    let server_time: String

    enum CodingKeys: String, CodingKey { case user, feed, unread_notifications, server_time }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(KaiXUserDTO.self, forKey: .user)
        // feed 逐条容错:单条坏帖只丢该条,不让首屏 bootstrap 整屏报错(与主 feed 一致)。
        feed = try container.decode(KaiXLossyDecodableArray<KaiXPostDTO>.self, forKey: .feed).elements
        unread_notifications = try container.decode(Int.self, forKey: .unread_notifications)
        server_time = try container.decode(String.self, forKey: .server_time)
    }
}

// MARK: - My Library (purchased + member-unlocked resources, services, orders)
// Mirrors GET /api/guide/my-library. Optional fields stay lenient so a single
// odd row never breaks the whole page.

struct KaiXGuideLibraryResponse: Codable, Equatable {
    let status: String?
    let isMember: Bool?
    let materials: [KaiXGuideLibraryMaterial]
    let services: [KaiXGuideLibraryService]
    let orders: [KaiXGuideLibraryOrder]
}

struct KaiXGuideLibraryMaterial: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let slug: String?
    let categoryKey: String?
    let productType: String?
    let coverImage: String?
    let entitlementSource: String?   // "own" | "member"
    let grantedAt: String?
    let hasFile: Bool?

    var isMemberUnlocked: Bool { (entitlementSource ?? "own") == "member" }
}

struct KaiXGuideLibraryService: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let productId: String?
    let productSlug: String?
    let productTitle: String?
    let serviceType: String?
    let status: String?
    let adminNote: String?
    let createdAt: String?
    let updatedAt: String?
}

struct KaiXGuideLibraryOrder: Codable, Equatable, Identifiable, Hashable {
    let kind: String?                // "purchase" | "topup"
    let orderNo: String?
    let title: String?
    let productSlug: String?
    let status: String?
    let provider: String?
    let paymentMethod: String?
    let amount: Int?
    let currency: String?
    let pricePoints: Int?
    let createdAt: String?

    var id: String { "\(kind ?? "")-\(orderNo ?? "")-\(createdAt ?? "")" }
    var isTopUp: Bool { (kind ?? "") == "topup" }
}

// MARK: - Machi AI (原创 in-app assistant)
//
// Plain camelCase mirrors of /api/guide/ai/* responses. The underlying
// provider/model is never present in any of these payloads — to the client
// this is simply "Machi AI". Fields are optional so an older backend (or a
// trimmed response) decodes without crashing.

struct KaiXGuideAIRouteDTO: Codable, Equatable, Hashable {
    let kind: String?
    let slug: String?
    let id: String?
}

struct KaiXGuideAISourceDTO: Codable, Equatable, Hashable, Identifiable {
    let type: String?
    let title: String?
    let subtitle: String?
    let route: KaiXGuideAIRouteDTO?
    // 契约 C-4 导购字段(仅 product 项,服务端键名精确为 price_points / is_free)。
    // 旧 payload 缺省 → 两者为 nil,chip 不显示价签。
    let price_points: Int?
    let is_free: Bool?

    var id: String {
        [type, title, route?.slug, route?.id].compactMap { $0 }.joined(separator: "|")
    }
}

struct KaiXGuideAISuggestionDTO: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let title: String
    let category: String?
}

struct KaiXGuideAIAbilityDTO: Codable, Equatable, Hashable, Identifiable {
    let key: String
    let title: String
    let description: String?
    let memberOnly: Bool?
    var id: String { key }
}

// MARK: - JLPT 备考专区 (#4)

struct KaiXGuideJLPTLevelDTO: Codable, Equatable, Hashable, Identifiable {
    let key: String
    let label: String
    let summary: String
    var id: String { key }
}

struct KaiXGuideJLPTHeroDTO: Codable, Equatable, Hashable {
    let title: String?
    let subtitle: String?
}

struct KaiXGuideJLPTStudyPlanDTO: Codable, Equatable, Hashable {
    let title: String?
    let subtitle: String?
    let route: String?
}

struct KaiXGuideJLPTZoneResponse: Codable, Equatable {
    let status: String?
    let country: String?
    let hero: KaiXGuideJLPTHeroDTO?
    let levels: [KaiXGuideJLPTLevelDTO]?
    let articles: [KaiXGuideArticleDTO]?
    let resources: [KaiXGuideProductDTO]?
    let faq: [KaiXGuideFaqDTO]?
    let studyPlan: KaiXGuideJLPTStudyPlanDTO?
    let disclaimer: String?
    /// Live BE6 overlay (counts + per-user streak + exam countdown).
    let jlptCore: KaiXJLPTZoneCore?
}

struct KaiXGuideAIConversationDTO: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let title: String?
    let lastMessagePreview: String?
    let messageCount: Int?
    let country: String?
    let language: String?
    let createdAt: String?
    let updatedAt: String?
}

struct KaiXGuideAIMessageDTO: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let role: String
    let content: String
    let createdAt: String?
    let sources: [KaiXGuideAISourceDTO]?
}

struct KaiXGuideAIUsageDTO: Codable, Equatable, Hashable {
    let membershipActive: Bool?
    let remainingFreeUses: Int?
    let upgradeSuggested: Bool?
}

struct KaiXGuideAIBootstrapResponse: Codable, Equatable {
    let status: String?
    let membershipActive: Bool?
    let remainingFreeUses: Int?
    let suggestions: [KaiXGuideAISuggestionDTO]?
    let abilities: [KaiXGuideAIAbilityDTO]?
    let disclaimer: String?
}

struct KaiXGuideAIConversationsResponse: Codable, Equatable {
    let status: String?
    let items: [KaiXGuideAIConversationDTO]?
}

struct KaiXGuideAIMessagesResponse: Codable, Equatable {
    let status: String?
    let conversation: KaiXGuideAIConversationDTO?
    let items: [KaiXGuideAIMessageDTO]?
}

struct KaiXGuideAIChatResponse: Codable, Equatable {
    let status: String?
    let conversationId: String?
    let message: KaiXGuideAIMessageDTO?
    let usage: KaiXGuideAIUsageDTO?
}

struct KaiXGuideAIFeedbackResponse: Codable, Equatable {
    let status: String?
    let rating: String?
}

// MARK: - JLPT 备考核心 (BE6/iOS-3): 题库 / 定级 / 打卡 / 单词 / 在线考试 / 日历
//
// Contract mirrors `server_jlpt.py` (camelCase JSON). Compliance: all study
// content is original / licensed-import, never unauthorized past-paper text.

/// One practice / exam / placement question. `answerIndex` + `explanation` are
/// only present after the user has answered (review book, exam回看, or the local
/// grade result), so both stay optional.
struct KaiXJLPTQuestionDTO: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let level: String
    let section: String
    let sectionLabel: String?
    let questionType: String?
    let stem: String
    let passage: String?
    let audioMediaId: String?
    /// 听力题音频的可播放 URL(服务端 LEFT JOIN media 解析;非听力为空)。相对
    /// /media/... 由 kaixMediaURL 拼后端 base。
    let audioUrl: String?
    let choices: [String]
    let difficulty: Int?
    let isMemberOnly: Bool?
    // Post-answer reveal (review / exam breakdown).
    let answerIndex: Int?
    let explanation: String?
    // Exam / review breakdown overlays (server merges these onto the question).
    let selectedIndex: Int?
    let correct: Bool?
}

struct KaiXJLPTPracticeResponse: Codable, Equatable {
    let status: String?
    let level: String?
    let section: String?
    let membershipActive: Bool?
    let questions: [KaiXJLPTQuestionDTO]?
    let disclaimer: String?
}

/// Result of grading one attempt (`/attempt`). `correctIndex` reveals the key so
/// the client can flip the card and teach.
struct KaiXJLPTAttemptResult: Codable, Equatable {
    let status: String?
    let questionId: String?
    let correct: Bool?
    let correctIndex: Int?
    let selectedIndex: Int?
    let explanation: String?
}

struct KaiXJLPTReviewResponse: Codable, Equatable {
    let status: String?
    let questions: [KaiXJLPTQuestionDTO]?
    let disclaimer: String?
}

struct KaiXJLPTSectionStat: Codable, Equatable, Hashable, Identifiable {
    let section: String
    let label: String?
    let total: Int?
    let correct: Int?
    let accuracy: Double?
    var id: String { section }
}

struct KaiXJLPTStatsResponse: Codable, Equatable {
    let status: String?
    let level: String?
    let total: Int?
    let correct: Int?
    let accuracy: Double?
    let sections: [KaiXJLPTSectionStat]?
}

struct KaiXJLPTStreakDay: Codable, Equatable, Hashable, Identifiable {
    let date: String
    let done: Bool
    var id: String { date }
}

struct KaiXJLPTStreak: Codable, Equatable {
    let currentStreak: Int?
    let longestStreak: Int?
    let todayDone: Bool?
    let totalDays: Int?
    let last7days: [KaiXJLPTStreakDay]?
}

struct KaiXJLPTStreakResponse: Codable, Equatable {
    let status: String?
    let currentStreak: Int?
    let longestStreak: Int?
    let todayDone: Bool?
    let totalDays: Int?
    let last7days: [KaiXJLPTStreakDay]?
}

struct KaiXJLPTExamDate: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let region: String?
    let sessionLabel: String?
    let examDate: String?
    let regOpenDate: String?
    let regCloseDate: String?
    let note: String?
}

struct KaiXJLPTCountdown: Codable, Equatable, Hashable {
    let sessionLabel: String?
    let examDate: String?
    let daysRemaining: Int?
}

struct KaiXJLPTExamDatesResponse: Codable, Equatable {
    let status: String?
    let region: String?
    let examDates: [KaiXJLPTExamDate]?
    let countdown: KaiXJLPTCountdown?
}

/// Live per-user overlay embedded in the zone payload (counts + streak +
/// countdown). Drives which entry cards light up.
struct KaiXJLPTZoneCore: Codable, Equatable {
    let hasPractice: Bool?
    let hasPlacement: Bool?
    let hasVocab: Bool?
    let hasExams: Bool?
    let examCountdown: KaiXJLPTCountdown?
    let streak: KaiXJLPTStreak?
}

struct KaiXJLPTPlacementStartResponse: Codable, Equatable {
    let status: String?
    let questions: [KaiXJLPTQuestionDTO]?
    let note: String?
}

struct KaiXJLPTPlacementResult: Codable, Equatable {
    let status: String?
    let recommendedLevel: String?
    let confidence: Double?
    let sectionBreakdown: [KaiXJLPTSectionStat]?
    let weakSections: [String]?
    let suggestedDailyMinutes: Int?
    let answered: Int?
    let studyPlanRoute: String?
}

/// Answer payload the client posts to `/placement/submit`.
struct KaiXJLPTPlacementAnswer: Codable, Equatable {
    let questionId: String
    let selectedIndex: Int
}

// ── vocab ────────────────────────────────────────────────────────────────────

struct KaiXJLPTVocabDeck: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let level: String?
    let title: String?
    let description: String?
    let wordCount: Int?
    let isMemberOnly: Bool?
}

struct KaiXJLPTVocabDecksResponse: Codable, Equatable {
    let status: String?
    let decks: [KaiXJLPTVocabDeck]?
}

struct KaiXJLPTVocabWord: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let level: String?
    let word: String
    let reading: String?
    let meaningZh: String?
    let meaningEn: String?
    let pos: String?
    let example: String?
    let exampleZh: String?
    let mastered: Bool?
}

struct KaiXJLPTVocabDeckResponse: Codable, Equatable {
    let status: String?
    let deck: KaiXJLPTVocabDeck?
    let words: [KaiXJLPTVocabWord]?
}

struct KaiXJLPTVocabMarkResponse: Codable, Equatable {
    let status: String?
    let wordId: String?
    let state: String?
}

struct KaiXJLPTVocabProgress: Codable, Equatable {
    let status: String?
    let level: String?
    let total: Int?
    let mastered: Int?
    let learning: Int?
    let progress: Double?
}

/// A generated vocab-quiz question (自 build_vocab_quiz; answer key is server-side).
struct KaiXJLPTVocabQuizQuestion: Codable, Equatable, Hashable, Identifiable {
    let wordId: String
    let word: String?
    let reading: String?
    let stem: String
    let choices: [String]
    var id: String { wordId }
}

struct KaiXJLPTVocabQuizStartResponse: Codable, Equatable {
    let status: String?
    let sessionId: String?
    let level: String?
    let kind: String?
    let total: Int?
    let questions: [KaiXJLPTVocabQuizQuestion]?
}

struct KaiXJLPTVocabQuizResult: Codable, Equatable, Hashable, Identifiable {
    let index: Int
    let selectedIndex: Int?
    let correctIndex: Int?
    let correct: Bool?
    var id: Int { index }
}

struct KaiXJLPTVocabQuizSubmitResponse: Codable, Equatable {
    let status: String?
    let sessionId: String?
    let total: Int?
    let correct: Int?
    let score: Int?
    let passed: Bool?
    let durationSeconds: Int?
    let results: [KaiXJLPTVocabQuizResult]?
}

// ── online exams ─────────────────────────────────────────────────────────────

struct KaiXJLPTExam: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let level: String?
    let title: String?
    let kind: String?
    let section: String?
    let sectionLabel: String?
    let questionCount: Int?
    let durationSeconds: Int?
    let passScore: Int?
    let isMemberOnly: Bool?
    /// 'percent'(默认) 或 'jlpt_scaled'(全真卷:提交后按官方计分结构出缩放分)。
    let scoreMode: String?
    /// 分科整卷:父卷/子科目标记与聚合。
    let parentExamId: String?
    let isPaper: Bool?
    let isSection: Bool?
    let sortOrder: Int?
    /// 父卷(isPaper)聚合的子科目数(list_exams 计算)。
    let sectionCount: Int?
    /// 开考消耗的 Machi 币(0=免费);会员价 5 折。
    let coinCost: Int?
    let coinCostMember: Int?
}

/// 分科整卷详情:父卷 + 有序子科目(客户端按顺序逐段推进)。
struct KaiXJLPTPaperDetail: Codable, Equatable {
    let status: String?
    let paper: KaiXJLPTExam
    let sections: [KaiXJLPTExam]?
    let disclaimer: String?
}

/// 分科整卷合并成绩里的单科条目。
struct KaiXJLPTPaperResultSection: Codable, Equatable, Hashable, Identifiable {
    let examId: String
    let section: String?
    let sectionLabel: String?
    let title: String?
    let done: Bool?
    let sessionId: String?
    let total: Int?
    let correct: Int?
    let score: Int?
    let passed: Bool?
    let durationSeconds: Int?
    let scaled: KaiXJLPTScaledResult?
    var id: String { examId }
}

/// 聴解(参考)百分比段。
struct KaiXJLPTPaperListening: Codable, Equatable, Hashable {
    let score: Int?
    let correct: Int?
    let total: Int?
    let passed: Bool?
}

/// 分科整卷合并成绩:笔试缩放分 + 聴解百分比。
struct KaiXJLPTPaperResult: Codable, Equatable {
    let status: String?
    let paperId: String?
    let level: String?
    let title: String?
    let complete: Bool?
    let sections: [KaiXJLPTPaperResultSection]?
    let scaled: KaiXJLPTScaledResult?
    let listening: KaiXJLPTPaperListening?
    let disclaimer: String?
}

/// JLPT 缩放分的单科条目(言語知識/読解,或 N4·N5 的合并科)。
struct KaiXJLPTScaledScale: Codable, Equatable, Hashable {
    let key: String?
    let label: String?
    let raw: Int?
    let rawMax: Int?
    let scaled: Int?
    let scaledMax: Int?
    let sectionMin: Int?
    let passed: Bool?
}

/// score_mode='jlpt_scaled' 的全真卷在 /exam/submit、/exam/session/{id}、
/// /exam/history 里附带的整块缩放结果(笔试参考,不含聴解)。
struct KaiXJLPTScaledResult: Codable, Equatable, Hashable {
    let mode: String?
    let level: String?
    let writtenTotal: Int?
    let writtenMax: Int?
    let passLineWritten: Int?
    let passedWrittenReference: Bool?
    let scales: [KaiXJLPTScaledScale]?
    let officialPassTotal: Int?
    let officialTotalMax: Int?
    let note: String?
}

struct KaiXJLPTExamsResponse: Codable, Equatable {
    let status: String?
    let exams: [KaiXJLPTExam]?
}

/// One previously-saved answer echoed back when `/exam/start` resumes an
/// in-progress session (B15-D). Snake/camel dual-key tolerant.
struct KaiXJLPTExamResumeAnswer: Codable, Equatable, Hashable {
    let questionId: String?
    let selectedIndex: Int?

    enum CodingKeys: String, CodingKey { case questionId, selectedIndex }
    private enum SnakeKeys: String, CodingKey {
        case questionId = "question_id"
        case selectedIndex = "selected_index"
    }

    init(questionId: String?, selectedIndex: Int?) {
        self.questionId = questionId
        self.selectedIndex = selectedIndex
    }

    init(from decoder: Decoder) throws {
        let camel = try decoder.container(keyedBy: CodingKeys.self)
        let snake = try decoder.container(keyedBy: SnakeKeys.self)
        questionId = try camel.decodeIfPresent(String.self, forKey: .questionId)
            ?? snake.decodeIfPresent(String.self, forKey: .questionId)
        selectedIndex = try camel.decodeIfPresent(Int.self, forKey: .selectedIndex)
            ?? snake.decodeIfPresent(Int.self, forKey: .selectedIndex)
    }
}

struct KaiXJLPTExamStartResponse: Codable, Equatable {
    let status: String?
    let sessionId: String?
    let examId: String?
    let level: String?
    let title: String?
    let durationSeconds: Int?
    let passScore: Int?
    let total: Int?
    let questions: [KaiXJLPTQuestionDTO]?
    let disclaimer: String?
    // Resume overlay (B15-D) — present only when the server handed back an
    // existing in-progress session instead of a fresh one. All optional so an
    // older server (which omits them) keeps decoding fine.
    let resumed: Bool?
    let answers: [KaiXJLPTExamResumeAnswer]?
    /// Server-computed seconds left on the clock — the server is the timing
    /// authority on resume; the client re-anchors its deadline to this.
    let remainingSeconds: Int?

    /// 'percent' 或 'jlpt_scaled' — 客户端据此在开考页预告 180 分制出分。
    let scoreMode: String?

    enum CodingKeys: String, CodingKey {
        case status, sessionId, examId, level, title, durationSeconds, passScore,
             total, questions, disclaimer, resumed, answers, remainingSeconds, scoreMode
    }
    private enum SnakeKeys: String, CodingKey {
        case remainingSeconds = "remaining_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        examId = try c.decodeIfPresent(String.self, forKey: .examId)
        level = try c.decodeIfPresent(String.self, forKey: .level)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        passScore = try c.decodeIfPresent(Int.self, forKey: .passScore)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        questions = try c.decodeIfPresent([KaiXJLPTQuestionDTO].self, forKey: .questions)
        disclaimer = try c.decodeIfPresent(String.self, forKey: .disclaimer)
        resumed = try c.decodeIfPresent(Bool.self, forKey: .resumed)
        answers = try c.decodeIfPresent([KaiXJLPTExamResumeAnswer].self, forKey: .answers)
        scoreMode = try c.decodeIfPresent(String.self, forKey: .scoreMode)
        let snake = try decoder.container(keyedBy: SnakeKeys.self)
        remainingSeconds = try c.decodeIfPresent(Int.self, forKey: .remainingSeconds)
            ?? snake.decodeIfPresent(Int.self, forKey: .remainingSeconds)
    }
}

struct KaiXJLPTExamAnswerResponse: Codable, Equatable {
    let status: String?
    let saved: Bool?
    let questionId: String?
}

/// Result of `/exam/submit` and the shape returned by `/exam/session/{id}`.
struct KaiXJLPTExamResult: Codable, Equatable {
    let status: String?
    let sessionId: String?
    let examId: String?
    let level: String?
    let total: Int?
    let correct: Int?
    let score: Int?
    let passed: Bool?
    let passScore: Int?
    let scoreMode: String?
    let scaled: KaiXJLPTScaledResult?
    let durationSeconds: Int?
    let questions: [KaiXJLPTQuestionDTO]?
    let disclaimer: String?
}

struct KaiXJLPTExamHistoryItem: Codable, Equatable, Hashable, Identifiable {
    let sessionId: String
    let examId: String?
    let title: String?
    let kind: String?
    let level: String?
    let total: Int?
    let correct: Int?
    let score: Int?
    let passed: Bool?
    let scoreMode: String?
    let scaled: KaiXJLPTScaledResult?
    let durationSeconds: Int?
    let startedAt: String?
    let submittedAt: String?
    var id: String { sessionId }
}

struct KaiXJLPTExamHistoryResponse: Codable, Equatable {
    let status: String?
    let sessions: [KaiXJLPTExamHistoryItem]?
}

struct KaiXJLPTExplainResponse: Codable, Equatable {
    let status: String?
    let questionId: String?
    let explanation: String?
    let usage: KaiXGuideAIUsageDTO?
    let disclaimer: String?
}
