import SwiftUI
import UIKit

// School / company directory + reviews views, split out of GuideViews.swift
// for maintainability. Shares guideText / GuideMetaRow / GuideSchoolFilterSheet
// (now module-internal) with the rest of the Guide views.

struct GuideSchoolListView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var schools: [KaiXGuideSchoolDTO] = []
    @State private var keyword = ""
    @State private var schoolType = ""
    @State private var regionGroup = ""
    @State private var prefecture = ""
    @State private var field = ""
    @State private var supportFilter = ""
    @State private var sort = "recommended"
    @State private var showFilterSheet = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }
    private var activeFilterCount: Int {
        [prefecture, field, supportFilter, regionGroup].filter { !$0.isEmpty }.count + (sort != "recommended" ? 1 : 0)
    }

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        schoolSearchHeader
                        schoolFilters
                        if isLoading {
                            LoadingView()
                        } else if let errorMessage {
                            ErrorStateView(message: errorMessage) {
                                Task { await load() }
                            }
                        } else if schools.isEmpty {
                            EmptyStateView(title: guideText(language, "暂无匹配学校", "条件に合う学校はありません", "No matching schools"), subtitle: guideText(language, "试试其他学校类型、地区或关键词。", "学校種別、地域、キーワードを変えてみてください。", "Try another school type, region, or keyword."), systemImage: "graduationcap")
                        } else {
                            ForEach(schools) { school in
                                GuideSchoolCard(school: school)
                            }
                        }
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            }
        }
        .navigationTitle(guideText(language, "日本学校库", "日本の学校データベース", "Japan School Library"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: [schoolType, regionGroup, prefecture, field, supportFilter, sort].joined(separator: ":")) { await load() }
        .sheet(isPresented: $showFilterSheet) {
            GuideSchoolFilterSheet(schoolType: $schoolType, regionGroup: $regionGroup, prefecture: $prefecture,
                                   field: $field, supportFilter: $supportFilter, sort: $sort)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var schoolSearchHeader: some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    GuideIconBubble(icon: "graduationcap.fill", color: KXColor.rankSky)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(guideText(language, "日本学校库", "日本の学校データベース", "Japan School Library"))
                            .font(.title3.weight(.bold))
                        Text(guideText(language, "大学、大学院、专门学校与语言学校的官方入口", "大学、大学院、専門学校、語学学校の公式入口", "Official entry points for universities, graduate schools, vocational schools, and language schools"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(guideText(language, "搜索学校名、学科、城市", "学校名・学科・都市を検索", "Search school name, major, or city"), text: $keyword)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await load() } }
                    Button(guideText(language, "搜索", "検索", "Search")) {
                        Task { await load() }
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
                .padding(11)
                .background(KXColor.softBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // Compact filter bar: one row of main school types, one row of quick chips +
    // a 筛选 button that opens the full filter bottom sheet (no more 4 stacked rows).
    private var schoolFilters: some View {
        VStack(alignment: .leading, spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([
                        ("", guideText(language, "全部", "すべて", "All")),
                        ("university", guideText(language, "大学", "大学", "University")),
                        ("graduate_school", guideText(language, "大学院", "大学院", "Graduate school")),
                        ("vocational_school", guideText(language, "专门学校", "専門学校", "Vocational school")),
                        ("language_school", guideText(language, "语言学校", "語学学校", "Language school")),
                    ], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: schoolType == value) {
                            schoolType = value
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        GuidePillButton(title: guideText(language, "首都圈", "首都圏", "Capital area"), isSelected: regionGroup == "capital_area") {
                            regionGroup = regionGroup == "capital_area" ? "" : "capital_area"
                        }
                        GuidePillButton(title: guideText(language, "关西圈", "関西圏", "Kansai area"), isSelected: regionGroup == "kansai_area") {
                            regionGroup = regionGroup == "kansai_area" ? "" : "kansai_area"
                        }
                        GuidePillButton(title: guideText(language, "留学生可申请", "留学生出願可", "International students"), isSelected: supportFilter == "international") {
                            supportFilter = supportFilter == "international" ? "" : "international"
                        }
                        GuidePillButton(title: guideText(language, "英文项目", "英語プログラム", "English programs"), isSelected: supportFilter == "english") {
                            supportFilter = supportFilter == "english" ? "" : "english"
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button {
                    showFilterSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text(activeFilterCount > 0 ? guideText(language, "筛选 \(activeFilterCount)", "絞り込み \(activeFilterCount)", "Filters \(activeFilterCount)") : guideText(language, "筛选", "絞り込み", "Filters"))
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(activeFilterCount > 0 ? Color.white : KXColor.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(activeFilterCount > 0 ? KXColor.accent : KXColor.accentSoft, in: Capsule())
                }
                .buttonStyle(.fullArea)
        .contentShape(Rectangle())
            }
        }
    }

    private func load() async {
        guard country == "jp" else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await KaiXAPIClient.shared.guideSchools(
                country: country,
                regionGroup: regionGroup.isEmpty ? nil : regionGroup,
                prefecture: prefecture.isEmpty ? nil : prefecture,
                schoolType: schoolType.isEmpty ? nil : schoolType,
                field: field.isEmpty ? nil : field,
                acceptsInternationalStudents: supportFilter == "international" ? true : nil,
                hasEnglishProgram: supportFilter == "english" ? true : nil,
                hasJapaneseProgram: supportFilter == "japanese" ? true : nil,
                hasScholarship: supportFilter == "scholarship" ? true : nil,
                hasDormitory: supportFilter == "dormitory" ? true : nil,
                hasCareerSupport: supportFilter == "career" ? true : nil,
                hasLanguageSupport: supportFilter == "language_support" ? true : nil,
                keyword: keyword.isEmpty ? nil : keyword,
                sort: sort,
                pageSize: 50
            )
            schools = response.items
            // Cache the last-seen list so an offline reopen shows samples, not a blank.
            KaiXSnapshotCache.save(response.items, key: "guide-schools-\(country)")
        } catch {
            // Offline: prefer the last-seen list as samples so the page stays
            // visually complete instead of collapsing to an error icon. Only fall
            // back to the friendly error copy when there is no cache at all.
            if let cached = KaiXSnapshotCache.load([KaiXGuideSchoolDTO].self, key: "guide-schools-\(country)"), !cached.isEmpty {
                schools = cached
                errorMessage = nil
            } else {
                errorMessage = guideText(
                    language,
                    "暂时连不上服务器，学校库没能加载。联网后下拉刷新即可查看完整资料。",
                    "サーバーに接続できず、学校データベースを読み込めません。通信が回復したら下に引いて更新してください。",
                    "Can't reach the server to load the school library right now. Pull to refresh once you're back online."
                )
            }
        }
    }
}

struct GuideCompanyListView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var companies: [KaiXGuideCompanyDTO] = []
    @State private var keyword = ""
    @State private var regionGroup = ""
    @State private var industry = ""
    @State private var city = ""
    @State private var companySize = ""
    @State private var employmentType = ""
    @State private var supportFilter = ""
    @State private var sort = "recommended"
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        companySearchHeader
                        companyFilters
                        if isLoading {
                            LoadingView()
                        } else if let errorMessage {
                            ErrorStateView(message: errorMessage) {
                                Task { await load() }
                            }
                        } else if companies.isEmpty {
                            EmptyStateView(title: guideText(language, "暂无匹配公司", "条件に合う会社はありません", "No matching companies"), subtitle: guideText(language, "试试其他关键词、地区或放宽筛选。", "別のキーワードや地域、ゆるい条件で試してください。", "Try another keyword, region, or broader filters."), systemImage: "building.2")
                        } else {
                            ForEach(companies) { company in
                                GuideCompanyCard(company: company)
                            }
                        }
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            }
        }
        .navigationTitle(guideText(language, "外国人就职公司库", "外国人向け就職企業データベース", "Foreigner-Friendly Company Library"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: [regionGroup, industry, city, companySize, employmentType, supportFilter, sort].joined(separator: ":")) { await load() }
    }

    private var companySearchHeader: some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    GuideIconBubble(icon: "building.2.fill", color: KXColor.rankTeal)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(guideText(language, "外国人就职公司库", "外国人向け就職企業データベース", "Foreigner-Friendly Company Library"))
                            .font(.title3.weight(.bold))
                        Text(guideText(language, "以官方招聘页、签证支持和真实评价为主", "公式採用ページ、ビザ支援、実体験レビューを重視", "Focused on official career pages, visa support, and real reviews"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(guideText(language, "搜索公司名、行业、岗位", "会社名・業界・職種を検索", "Search company, industry, or role"), text: $keyword)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await load() } }
                    Button(guideText(language, "搜索", "検索", "Search")) {
                        Task { await load() }
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
                .padding(11)
                .background(KXColor.softBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var companyFilters: some View {
        VStack(alignment: .leading, spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([("", guideText(language, "全部地区", "すべての地域", "All areas")), ("tokyo", "Tokyo"), ("yokohama", "Yokohama"), ("osaka", "Osaka"), ("kyoto", "Kyoto"), ("kobe", "Kobe")], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: city == value) {
                            city = value
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([("", guideText(language, "日本全国", "日本全国", "All Japan")), ("capital_area", guideText(language, "首都圈", "首都圏", "Capital area")), ("kansai_area", guideText(language, "关西圈", "関西圏", "Kansai area"))], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: regionGroup == value) {
                            regionGroup = value
                        }
                    }
                    ForEach([("", guideText(language, "全部行业", "すべての業界", "All industries")), ("it_internet", "IT"), ("software", guideText(language, "软件", "ソフトウェア", "Software")), ("ai_data", "AI/Data"), ("manufacturing", guideText(language, "制造", "製造", "Manufacturing")), ("finance", guideText(language, "金融", "金融", "Finance")), ("consulting", guideText(language, "咨询", "コンサル", "Consulting")), ("game_entertainment", guideText(language, "游戏", "ゲーム", "Games"))], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: industry == value) {
                            industry = value
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([("", guideText(language, "全部规模", "すべての規模", "All sizes")), ("enterprise", guideText(language, "大手", "大手", "Enterprise")), ("large", guideText(language, "大型", "大規模", "Large")), ("medium", guideText(language, "中型", "中規模", "Mid-size")), ("startup", guideText(language, "初创", "スタートアップ", "Startup"))], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: companySize == value) {
                            companySize = value
                        }
                    }
                    ForEach([("", guideText(language, "全部雇佣", "すべての雇用", "All employment")), ("new_graduate", "新卒"), ("mid_career", "中途"), ("internship", guideText(language, "实习", "インターン", "Internship")), ("global_hire", "Global hire")], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: employmentType == value) {
                            employmentType = value
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([("visa", guideText(language, "签证支持", "ビザ支援", "Visa support")), ("foreign", guideText(language, "外国人友好", "外国人フレンドリー", "Foreigner-friendly")), ("english", guideText(language, "英文岗位", "英語ポジション", "English roles")), ("global", "Global career"), ("employees", guideText(language, "外国员工", "外国籍社員", "Foreign employees"))], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: supportFilter == value) {
                            supportFilter = supportFilter == value ? "" : value
                        }
                    }
                    ForEach([("recommended", guideText(language, "推荐", "おすすめ", "Recommended")), ("data_quality", guideText(language, "完整度", "充実度", "Completeness")), ("recently_updated", guideText(language, "最近更新", "最近更新", "Recently updated")), ("review_count", guideText(language, "评论数", "レビュー数", "Review count")), ("name_jp_asc", guideText(language, "日文名", "日本語名", "Japanese name"))], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: sort == value) {
                            sort = value
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func load() async {
        guard country == "jp" else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await KaiXAPIClient.shared.guideCompanies(
                country: country,
                regionGroup: regionGroup.isEmpty ? nil : regionGroup,
                city: city.isEmpty ? nil : city,
                industry: industry.isEmpty ? nil : industry,
                companySize: companySize.isEmpty ? nil : companySize,
                employmentType: employmentType.isEmpty ? nil : employmentType,
                supportsWorkVisa: supportFilter == "visa" ? true : nil,
                acceptsForeignApplicants: supportFilter == "foreign" ? true : nil,
                hasEnglishPositions: supportFilter == "english" ? true : nil,
                hasGlobalRoles: supportFilter == "global" ? true : nil,
                hasForeignEmployees: supportFilter == "employees" ? true : nil,
                keyword: keyword.isEmpty ? nil : keyword,
                sort: sort,
                pageSize: 50
            )
            companies = response.items
            KaiXSnapshotCache.save(response.items, key: "guide-companies-\(country)")
        } catch {
            if let cached = KaiXSnapshotCache.load([KaiXGuideCompanyDTO].self, key: "guide-companies-\(country)"), !cached.isEmpty {
                companies = cached
                errorMessage = nil
            } else {
                errorMessage = guideText(
                    language,
                    "暂时连不上服务器，公司库没能加载。联网后下拉刷新即可查看完整资料。",
                    "サーバーに接続できず、企業データベースを読み込めません。通信が回復したら下に引いて更新してください。",
                    "Can't reach the server to load the company library right now. Pull to refresh once you're back online."
                )
            }
        }
    }
}

struct GuideSchoolDetailView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var response: KaiXGuideSchoolDetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var correctionText = ""
    @State private var isSubmitting = false
    @State private var toastMessage: String?

    let schoolId: String
    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else if isLoading {
                LoadingView()
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) {
                    Task { await load() }
                }
            } else if let response {
                let school = response.school
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        schoolHero(school)
                        schoolSignalPanel(school)
                        actionPanel(school)
                        programSection(response.programs)
                        admissionSection(response.admissions)
                        if !response.relatedArticles.isEmpty {
                            GuideArticleSection(title: guideText(language, "相关指南", "関連ガイド", "Related guides"), subtitle: nil, articles: response.relatedArticles, compact: true)
                        }
                        if !response.relatedProducts.isEmpty {
                            GuideProductsSection(products: response.relatedProducts)
                        }
                        GuideNotePanel(text: response.disclaimer)
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            } else {
                EmptyStateView(title: guideText(language, "学校不存在", "学校が見つかりません", "School not found"), subtitle: guideText(language, "它可能已被移动或下线。", "移動または非公開になった可能性があります。", "It may have been moved or unpublished."), systemImage: "graduationcap")
            }
        }
        .navigationTitle(guideText(language, "学校详情", "学校詳細", "School details"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(country):\(schoolId)") { await load() }
        .alert("Machi Guide", isPresented: Binding(
            get: { toastMessage != nil },
            set: { if !$0 { toastMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(toastMessage ?? "")
        }
    }

    private func schoolHero(_ school: KaiXGuideSchoolDTO) -> some View {
        KXCard(padding: 18, radius: 24) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 13) {
                    GuideIconBubble(icon: "graduationcap.fill", color: KXColor.rankSky)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(school.schoolName)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        if !school.schoolNameJp.isEmpty {
                            Text(school.schoolNameJp)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !school.schoolNameEn.isEmpty {
                            Text(school.schoolNameEn)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text([
                            GuideCopy.schoolTypeLabel(school.schoolType, language: language),
                            GuideCopy.cityLabel(school.city, language: language),
                            school.prefecture.isEmpty ? "" : school.prefecture,
                            school.ward ?? ""
                        ].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    GuideBadge(GuideCopy.sourceStatusLabel(school.verificationStatus, language: language), tint: KXColor.rankSky)
                }
                if !school.description.isEmpty {
                    Text(school.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FlowLayout(spacing: 6) {
                    ForEach(school.fieldsOfStudy.prefix(6), id: \.self) { field in
                        GuideBadge(field)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    if let url = GuideCopy.url(school.website) {
                        Link(destination: url) {
                            Label(guideText(language, "学校官网", "学校公式サイト", "School website"), systemImage: "link")
                        }
                    }
                    if let url = GuideCopy.url(school.internationalAdmissionUrl) {
                        Link(destination: url) {
                            Label(guideText(language, "国际招生/入试页面", "留学生入試ページ", "International admissions"), systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    if let url = GuideCopy.url(school.applicationUrl) {
                        Link(destination: url) {
                            Label(guideText(language, "申请入口", "出願入口", "Application portal"), systemImage: "square.and.pencil")
                        }
                    }
                    if let url = GuideCopy.url(school.scholarshipUrl) {
                        Link(destination: url) {
                            Label(guideText(language, "奖学金页面", "奨学金ページ", "Scholarships"), systemImage: "yensign.circle.fill")
                        }
                    }
                    if let url = GuideCopy.url(school.careerSupportUrl) {
                        Link(destination: url) {
                            Label(guideText(language, "就职支持", "就職支援", "Career support"), systemImage: "briefcase.fill")
                        }
                    }
                    if let url = GuideCopy.url(school.dormitoryUrl) {
                        Link(destination: url) {
                            Label(guideText(language, "宿舍信息", "寮情報", "Dormitory info"), systemImage: "house.fill")
                        }
                    }
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(KXColor.accent)
            }
        }
    }

    private func schoolSignalPanel(_ school: KaiXGuideSchoolDTO) -> some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text(guideText(language, "申请信息", "出願情報", "Application info"))
                    .font(.headline.weight(.bold))
                GuideMetaRow(title: guideText(language, "地址", "住所", "Address"), value: [school.postalCode ?? "", school.prefecture, school.city, school.ward ?? "", school.address ?? ""].filter { !$0.isEmpty }.joined(separator: " ").ifEmpty(guideText(language, "待补充", "未入力", "Pending")))
                GuideMetaRow(title: guideText(language, "学费", "学費", "Tuition"), value: GuideCopy.moneyRange(min: school.tuitionMin, max: school.tuitionMax, currency: school.currency, language: language))
                GuideMetaRow(title: guideText(language, "入学月份", "入学月", "Admission months"), value: GuideCopy.joinedOrPending(school.admissionMonths, language: language))
                GuideMetaRow(title: guideText(language, "日语要求", "日本語要件", "Japanese requirement"), value: GuideCopy.levelLabel(school.requiredJapaneseLevel, language: language))
                GuideMetaRow(title: guideText(language, "英语要求", "英語要件", "English requirement"), value: GuideCopy.levelLabel(school.requiredEnglishLevel, language: language))
                GuideMetaRow(title: guideText(language, "考试要求", "試験要件", "Exam requirements"), value: "JLPT \(GuideCopy.levelLabel(school.jlptRequired ?? "unknown", language: language)) · EJU \(GuideCopy.levelLabel(school.ejuRequired ?? "unknown", language: language)) · TOEFL \(GuideCopy.levelLabel(school.toeflRequired ?? "unknown", language: language)) · IELTS \(GuideCopy.levelLabel(school.ieltsRequired ?? "unknown", language: language))")
                GuideMetaRow(title: guideText(language, "学部/研究科", "学部/研究科", "Faculties/Graduate schools"), value: [
                    GuideCopy.joinedOrPending(school.faculties ?? [], language: language),
                    GuideCopy.joinedOrPending(school.graduateSchools ?? [], language: language),
                    GuideCopy.joinedOrPending(school.departments ?? [], language: language),
                ].filter { $0 != guideText(language, "待补充", "未入力", "Pending") }.joined(separator: " / ").ifEmpty(guideText(language, "待补充", "未入力", "Pending")))
                GuideMetaRow(title: guideText(language, "数据完整度", "データ充実度", "Data completeness"), value: "\(school.dataQualityScore ?? 0) / 100")
                GuideMetaRow(title: guideText(language, "数据来源", "データ出典", "Data source"), value: [school.sourceName ?? "", school.sourceLastCheckedAt ?? "", GuideCopy.sourceStatusLabel(school.verificationStatus, language: language)].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty(guideText(language, "待核验", "確認待ち", "Pending verification")))
                FlowLayout(spacing: 6) {
                    GuideBadge(GuideCopy.triStateLabel(school.isAcceptingInternationalStudents, trueText: guideText(language, "接受留学生", "留学生受入", "Accepts international students"), language: language), tint: KXColor.rankSky)
                    GuideBadge(GuideCopy.triStateLabel(school.hasEnglishProgram, trueText: guideText(language, "英文项目", "英語プログラム", "English programs"), language: language), tint: KXColor.rankTeal)
                    GuideBadge(GuideCopy.triStateLabel(school.hasJapaneseProgram, trueText: guideText(language, "日语项目", "日本語プログラム", "Japanese programs"), language: language), tint: KXColor.rankTeal)
                    GuideBadge(GuideCopy.triStateLabel(school.hasScholarship, trueText: guideText(language, "奖学金", "奨学金", "Scholarships"), language: language), tint: KXColor.rankGold)
                    GuideBadge(GuideCopy.triStateLabel(school.hasDormitory, trueText: guideText(language, "宿舍", "寮", "Dormitory"), language: language), tint: KXColor.rankViolet)
                    GuideBadge(GuideCopy.triStateLabel(school.hasCareerSupport, trueText: guideText(language, "就业支持", "就職支援", "Career support"), language: language), tint: KXColor.accent)
                    GuideBadge(GuideCopy.triStateLabel(school.hasLanguageSupport, trueText: guideText(language, "语言支持", "語学サポート", "Language support"), language: language), tint: KXColor.rankSky)
                }
            }
        }
    }

    private func actionPanel(_ school: KaiXGuideSchoolDTO) -> some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 11) {
                Button {
                    Task { await save(school) }
                } label: {
                    Label(isSubmitting ? guideText(language, "处理中", "処理中", "Processing") : guideText(language, "收藏学校", "学校を保存", "Save school"), systemImage: "bookmark.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(KXColor.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.fullArea)
        .contentShape(Rectangle())
                .disabled(isSubmitting)

                TextField(guideText(language, "发现官网、招生信息有误？在这里提交纠错", "公式サイトや入試情報の誤りを見つけたら、ここから修正を送信", "Found an error in the website or admissions info? Submit a correction here"), text: $correctionText, axis: .vertical)
                    .font(.footnote)
                    .lineLimit(2...4)
                    .padding(11)
                    .background(KXColor.softBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Button(guideText(language, "提交纠错", "修正を送信", "Submit correction")) {
                    Task { await submitCorrection(school) }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.accent)
                .disabled(correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
    }

    private func programSection(_ programs: [KaiXGuideSchoolProgramDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideSectionHeader(
                title: guideText(language, "项目与课程", "プログラム・コース", "Programs and courses"),
                subtitle: guideText(language, "只展示后台录入或官方来源补充的内容", "管理画面で登録済み、または公式ソースで補足された内容のみ表示します", "Only content entered in admin or backed by official sources is shown")
            )
            if programs.isEmpty {
                KXStatePanel(
                    title: guideText(language, "项目资料待补充", "プログラム情報は準備中です", "Program details are pending"),
                    subtitle: guideText(language, "当前学校还没有录入具体项目。", "この学校にはまだ具体的なプログラムが登録されていません。", "No specific programs have been entered for this school yet."),
                    systemImage: "list.bullet.rectangle"
                )
            } else {
                ForEach(programs) { program in
                    KXCard(padding: 14, radius: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(program.programName)
                                .font(.headline.weight(.bold))
                            if !program.programNameJp.isEmpty {
                                Text(program.programNameJp)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            FlowLayout(spacing: 6) {
                                GuideBadge(GuideCopy.levelLabel(program.degreeLevel, language: language), tint: KXColor.rankSky)
                                if !program.field.isEmpty { GuideBadge(program.field) }
                                if !program.languageOfInstruction.isEmpty { GuideBadge(program.languageOfInstruction, tint: KXColor.rankTeal) }
                                if program.durationMonths > 0 {
                                    GuideBadge(guideText(language, "\(program.durationMonths) 个月", "\(program.durationMonths) か月", "\(program.durationMonths) months"))
                                }
                            }
                            if !program.description.isEmpty {
                                Text(program.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let url = GuideCopy.url(program.applicationUrl) {
                                Link(guideText(language, "项目申请页面", "プログラム出願ページ", "Program application page"), destination: url)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(KXColor.accent)
                            }
                        }
                    }
                }
            }
        }
    }

    private func admissionSection(_ admissions: [KaiXGuideSchoolAdmissionDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideSectionHeader(
                title: guideText(language, "出愿与入试", "出願・入試", "Admissions and exams"),
                subtitle: guideText(language, "申请材料、选考方式和奖学金信息", "出願書類、選考方式、奨学金情報", "Application documents, selection methods, and scholarship info")
            )
            if admissions.isEmpty {
                KXStatePanel(
                    title: guideText(language, "出愿资料待补充", "出願情報は準備中です", "Admission details are pending"),
                    subtitle: guideText(language, "请以学校官方招生页面为准。", "学校の公式入試ページも必ず確認してください。", "Please also refer to the school's official admissions page."),
                    systemImage: "doc.text"
                )
            } else {
                ForEach(admissions) { admission in
                    KXCard(padding: 14, radius: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(admission.admissionType.isEmpty ? guideText(language, "入试信息", "入試情報", "Admission info") : admission.admissionType)
                                    .font(.headline.weight(.bold))
                                Spacer(minLength: 0)
                                if !admission.enrollmentMonth.isEmpty {
                                    GuideBadge(admission.enrollmentMonth, tint: KXColor.rankSky)
                                }
                            }
                            if !admission.selectionMethod.isEmpty {
                                GuideMetaRow(title: guideText(language, "选考", "選考", "Selection"), value: admission.selectionMethod)
                            }
                            if !admission.requiredDocuments.isEmpty {
                                GuideMetaRow(title: guideText(language, "材料", "書類", "Documents"), value: admission.requiredDocuments.joined(separator: language == .en ? ", " : "、"))
                            }
                            if !admission.scholarshipInfo.isEmpty {
                                GuideMetaRow(title: guideText(language, "奖学金", "奨学金", "Scholarship"), value: admission.scholarshipInfo)
                            }
                            if !admission.notes.isEmpty {
                                Text(admission.notes)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let url = GuideCopy.url(admission.sourceUrl) {
                                Link(guideText(language, "官方来源", "公式ソース", "Official source"), destination: url)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(KXColor.accent)
                            }
                        }
                    }
                }
            }
        }
    }

    private func save(_ school: KaiXGuideSchoolDTO) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await KaiXAPIClient.shared.saveGuideSchool(school.slug.isEmpty ? school.id : school.slug, on: true)
            toastMessage = guideText(language, "已收藏学校", "学校を保存しました", "School saved")
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    private func submitCorrection(_ school: KaiXGuideSchoolDTO) async {
        let message = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await KaiXAPIClient.shared.submitGuideCorrection(
                targetType: "school",
                targetId: school.id,
                message: message,
                sourceUrl: school.sourceUrl
            )
            correctionText = ""
            toastMessage = response.message
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    private func load() async {
        guard country == "jp" else {
            isLoading = false
            response = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            response = try await KaiXAPIClient.shared.guideSchool(schoolId, country: country)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuideCompanyDetailView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var response: KaiXGuideCompanyDetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var correctionText = ""
    @State private var isSubmitting = false
    @State private var toastMessage: String?

    let companyId: String
    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else if isLoading {
                LoadingView()
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) {
                    Task { await load() }
                }
            } else if let response {
                let company = response.company
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        companyHero(company)
                        companyActionPanel(company)
                        companyFactsPanel(company)
                        positionSection(response.positions ?? [])
                        scorePanel(company)
                        HStack(spacing: 10) {
                            Button {
                                router.open(.guideCompanyReviews(id: company.slug.isEmpty ? company.id : company.slug))
                            } label: {
                                Text(guideText(language, "查看评论（面试 \(response.interviewReviewCount) · 工作 \(response.workReviewCount)）", "レビューを見る（面接 \(response.interviewReviewCount) · 仕事 \(response.workReviewCount)）", "View reviews (interview \(response.interviewReviewCount) · work \(response.workReviewCount))"))
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(KXColor.accent, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.fullArea)
        .contentShape(Rectangle())
                        }
                        if let related = response.relatedArticles, !related.isEmpty {
                            GuideArticleSection(title: guideText(language, "相关指南", "関連ガイド", "Related guides"), subtitle: nil, articles: related, compact: true)
                        }
                        GuideNotePanel(text: response.disclaimer)
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            } else {
                EmptyStateView(title: guideText(language, "公司不存在", "会社が見つかりません", "Company not found"), subtitle: guideText(language, "它可能已被移动或下线。", "移動または非公開になった可能性があります。", "It may have been moved or unpublished."), systemImage: "building.2")
            }
        }
        .navigationTitle(guideText(language, "公司详情", "会社詳細", "Company details"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(country):\(companyId)") { await load() }
        .alert("Machi Guide", isPresented: Binding(
            get: { toastMessage != nil },
            set: { if !$0 { toastMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(toastMessage ?? "")
        }
    }

    private func companyHero(_ company: KaiXGuideCompanyDTO) -> some View {
        KXCard(padding: 18, radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 13) {
                    GuideIconBubble(icon: "building.2.fill", color: KXColor.rankTeal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(company.companyName)
                            .font(.title2.weight(.bold))
                        if !company.companyNameJp.isEmpty {
                            Text(company.companyNameJp)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let en = company.companyNameEn, !en.isEmpty {
                            Text(en)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text([company.industry, company.subIndustry ?? "", company.prefecture ?? "", GuideCopy.cityLabel(company.city, language: language), company.ward ?? "", company.size].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let status = company.verificationStatus, !status.isEmpty {
                        GuideBadge(GuideCopy.sourceStatusLabel(status, language: language), tint: KXColor.rankTeal)
                    }
                }
                if !company.description.isEmpty {
                    Text(company.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FlowLayout(spacing: 6) {
                    if let level = company.requiredJapaneseLevel, !level.isEmpty {
                        GuideBadge(guideText(language, "日语 \(GuideCopy.levelLabel(level, language: language))", "日本語 \(GuideCopy.levelLabel(level, language: language))", "Japanese \(GuideCopy.levelLabel(level, language: language))"), tint: KXColor.rankSky)
                    }
                    if let level = company.requiredEnglishLevel, !level.isEmpty {
                        GuideBadge(guideText(language, "英语 \(GuideCopy.levelLabel(level, language: language))", "英語 \(GuideCopy.levelLabel(level, language: language))", "English \(GuideCopy.levelLabel(level, language: language))"), tint: KXColor.rankTeal)
                    }
                    if let types = company.employmentTypes {
                        ForEach(types.prefix(3), id: \.self) { type in
                            GuideBadge(type)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    if let url = GuideCopy.url(company.website) {
                        Link(destination: url) {
                            Label(guideText(language, "公司官网", "会社公式サイト", "Company website"), systemImage: "link")
                        }
                    }
                    if let url = GuideCopy.url(company.careerUrl) {
                        Link(destination: url) {
                            Label(guideText(language, "官方招聘页", "公式採用ページ", "Official careers page"), systemImage: "briefcase.fill")
                        }
                    }
                    if let url = GuideCopy.url(company.newGraduateUrl) {
                        Link(destination: url) {
                            Label(guideText(language, "新卒採用", "新卒採用", "New graduate hiring"), systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    if let url = GuideCopy.url(company.midCareerUrl) {
                        Link(destination: url) {
                            Label(guideText(language, "中途採用", "中途採用", "Mid-career hiring"), systemImage: "person.text.rectangle")
                        }
                    }
                    if let url = GuideCopy.url(company.globalCareerUrl) {
                        Link(destination: url) {
                            Label("Global career", systemImage: "globe")
                        }
                    }
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(KXColor.accent)
            }
        }
    }

    private func companyActionPanel(_ company: KaiXGuideCompanyDTO) -> some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 11) {
                Button {
                    Task { await save(company) }
                } label: {
                    Label(isSubmitting ? guideText(language, "处理中", "処理中", "Processing") : guideText(language, "收藏公司", "会社を保存", "Save company"), systemImage: "bookmark.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(KXColor.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.fullArea)
        .contentShape(Rectangle())
                .disabled(isSubmitting)

                TextField(guideText(language, "发现招聘页、签证信息有误？在这里提交纠错", "採用ページやビザ情報の誤りを見つけたら、ここから修正を送信", "Found an error in careers or visa info? Submit a correction here"), text: $correctionText, axis: .vertical)
                    .font(.footnote)
                    .lineLimit(2...4)
                    .padding(11)
                    .background(KXColor.softBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Button(guideText(language, "提交纠错", "修正を送信", "Submit correction")) {
                    Task { await submitCorrection(company) }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.accent)
                .disabled(correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
    }

    private func companyFactsPanel(_ company: KaiXGuideCompanyDTO) -> some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text(guideText(language, "就职信号", "就職シグナル", "Career signals"))
                    .font(.headline.weight(.bold))
                GuideMetaRow(title: guideText(language, "行业", "業界", "Industry"), value: [company.industry, company.subIndustry ?? "", company.companySize ?? company.size].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty(guideText(language, "待补充", "未入力", "Pending")))
                GuideMetaRow(title: guideText(language, "地区", "地域", "Area"), value: [company.prefecture ?? "", GuideCopy.cityLabel(company.city, language: language), company.ward ?? ""].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty(guideText(language, "待补充", "未入力", "Pending")))
                GuideMetaRow(title: guideText(language, "地址", "住所", "Address"), value: [company.postalCode ?? "", company.prefecture ?? "", company.city, company.ward ?? "", company.address ?? ""].filter { !$0.isEmpty }.joined(separator: " ").ifEmpty(guideText(language, "待补充", "未入力", "Pending")))
                GuideMetaRow(title: guideText(language, "法人番号", "法人番号", "Corporate number"), value: company.corporateNumber?.isEmpty == false ? company.corporateNumber! : guideText(language, "待补充", "未入力", "Pending"))
                GuideMetaRow(title: guideText(language, "雇佣类型", "雇用形態", "Employment type"), value: GuideCopy.joinedOrPending(company.employmentTypes ?? [], language: language))
                GuideMetaRow(title: guideText(language, "语言要求", "言語要件", "Language requirements"), value: guideText(language, "日语 \(GuideCopy.levelLabel(company.requiredJapaneseLevel ?? "unknown", language: language)) · 英语 \(GuideCopy.levelLabel(company.requiredEnglishLevel ?? "unknown", language: language))", "日本語 \(GuideCopy.levelLabel(company.requiredJapaneseLevel ?? "unknown", language: language)) · 英語 \(GuideCopy.levelLabel(company.requiredEnglishLevel ?? "unknown", language: language))", "Japanese \(GuideCopy.levelLabel(company.requiredJapaneseLevel ?? "unknown", language: language)) · English \(GuideCopy.levelLabel(company.requiredEnglishLevel ?? "unknown", language: language))"))
                GuideMetaRow(title: guideText(language, "数据完整度", "データ充実度", "Data completeness"), value: "\(company.dataQualityScore ?? 0) / 100")
                GuideMetaRow(title: guideText(language, "数据来源", "データ出典", "Data source"), value: [company.sourceName ?? "", company.sourceLastCheckedAt ?? "", GuideCopy.sourceStatusLabel(company.verificationStatus ?? "", language: language)].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty(guideText(language, "待核验", "確認待ち", "Pending verification")))
                FlowLayout(spacing: 6) {
                    GuideBadge(GuideCopy.triStateLabel(company.acceptsForeignApplicants, trueText: guideText(language, "接受外国人申请", "外国人応募可", "Accepts foreign applicants"), language: language), tint: KXColor.rankTeal)
                    GuideBadge(GuideCopy.triStateLabel(company.supportsWorkVisa, trueText: guideText(language, "签证支持", "ビザ支援", "Visa support"), language: language), tint: KXColor.accent)
                    GuideBadge(GuideCopy.triStateLabel(company.supportsNewGraduate, trueText: "新卒", language: language), tint: KXColor.rankGold)
                    GuideBadge(GuideCopy.triStateLabel(company.supportsMidCareer, trueText: "中途", language: language), tint: KXColor.rankGold)
                    GuideBadge(GuideCopy.triStateLabel(company.hasEnglishPositions, trueText: guideText(language, "英文岗位", "英語ポジション", "English roles"), language: language), tint: KXColor.rankSky)
                    GuideBadge(GuideCopy.triStateLabel(company.hasGlobalRoles, trueText: "Global career", language: language), tint: KXColor.rankSky)
                    GuideBadge(GuideCopy.triStateLabel(company.hasForeignEmployees, trueText: guideText(language, "有外国籍员工", "外国籍社員あり", "Has foreign employees"), language: language), tint: KXColor.rankViolet)
                }
            }
        }
    }

    private func positionSection(_ positions: [KaiXGuideCompanyPositionDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideSectionHeader(
                title: guideText(language, "公开岗位", "公開求人", "Open roles"),
                subtitle: guideText(language, "来自后台录入或官方招聘页，薪资与条件以官方页面为准", "管理画面の登録情報または公式採用ページをもとに表示しています。給与と条件は公式ページを確認してください。", "Shown from admin-entered data or official careers pages. Salary and conditions should be checked on the official page.")
            )
            if positions.isEmpty {
                KXStatePanel(
                    title: guideText(language, "岗位资料待补充", "求人情報は準備中です", "Role details are pending"),
                    subtitle: guideText(language, "请优先查看公司官方招聘页。", "まずは会社の公式採用ページを確認してください。", "Please check the company's official careers page first."),
                    systemImage: "briefcase"
                )
            } else {
                ForEach(positions) { position in
                    GuideCompanyPositionCard(position: position)
                }
            }
        }
    }

    private func scorePanel(_ company: KaiXGuideCompanyDTO) -> some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(guideText(language, "真实评价", "リアルレビュー", "Real reviews"))
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text(company.reviewCount > 0 ? guideText(language, "\(company.reviewCount) 条评价", "\(company.reviewCount) 件のレビュー", "\(company.reviewCount) reviews") : guideText(language, "暂无评价", "レビューはまだありません", "No reviews yet"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let scores = company.scores {
                    GuideScoreRow(title: "外国人友好度", value: scores.foreignerFriendly)
                    GuideScoreRow(title: "面试难度", value: scores.interviewDifficulty)
                    GuideScoreRow(title: "加班强度", value: scores.overtime)
                    GuideScoreRow(title: "薪资福利", value: scores.salaryBenefit)
                    GuideScoreRow(title: "工作生活平衡", value: scores.workLifeBalance)
                    if let value = scores.visaSupport {
                        GuideScoreRow(title: guideText(language, "签证支持", "ビザ支援", "Visa support"), value: value)
                    }
                    if let value = scores.careerGrowth {
                        GuideScoreRow(title: guideText(language, "成长空间", "成長機会", "Growth opportunity"), value: value)
                    }
                } else {
                    Text(guideText(language, "暂无足够真实评价数据。评分将在用户提交并通过审核后显示，我们不预设主观分数。", "十分な実体験レビューはまだありません。スコアはユーザー投稿が審査後に表示され、Machi が主観的な点数を事前設定することはありません。", "There is not enough real review data yet. Scores appear after user submissions pass review; Machi does not preset subjective ratings."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func save(_ company: KaiXGuideCompanyDTO) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await KaiXAPIClient.shared.saveGuideCompany(company.slug.isEmpty ? company.id : company.slug, on: true)
            toastMessage = "已收藏公司"
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    private func submitCorrection(_ company: KaiXGuideCompanyDTO) async {
        let message = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await KaiXAPIClient.shared.submitGuideCorrection(
                targetType: "company",
                targetId: company.id,
                message: message,
                sourceUrl: company.sourceUrl ?? company.careerUrl ?? company.website
            )
            correctionText = ""
            toastMessage = response.message
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    private func load() async {
        guard country == "jp" else {
            isLoading = false
            response = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            response = try await KaiXAPIClient.shared.guideCompany(companyId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuideCompanyReviewsView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var response: KaiXGuideCompanyReviewsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab: ReviewTab = .interview
    @State private var isShowingComposer = false

    let companyId: String
    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }

    enum ReviewTab: String, CaseIterable, Identifiable {
        case interview
        case work
        var id: String { rawValue }
        func title(_ language: AppLanguage) -> String {
            self == .interview
                ? guideText(language, "面试评论", "面接レビュー", "Interview reviews")
                : guideText(language, "工作评价", "仕事レビュー", "Work reviews")
        }
    }

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else if isLoading {
                LoadingView()
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) {
                    Task { await load() }
                }
            } else if let response {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ForEach(ReviewTab.allCases) { tab in
                                GuidePillButton(title: "\(tab.title(language)) \(count(for: tab, response: response))", isSelected: selectedTab == tab) {
                                    selectedTab = tab
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        Button {
                            isShowingComposer = true
                        } label: {
                            Label(guideText(language, "写评论", "レビューを書く", "Write review"), systemImage: "square.and.pencil")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(KXColor.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.fullArea)
        .contentShape(Rectangle())

                        if selectedTab == .interview {
                            if response.interviewReviews.isEmpty {
                                EmptyStateView(title: guideText(language, "还没有面试评论", "面接レビューはまだありません", "No interview reviews yet"), subtitle: guideText(language, "到这里分享第一条真实面试经验。", "最初の実体験レビューを投稿してみましょう。", "Share the first real interview experience here."), systemImage: "bubble.left.and.bubble.right")
                            } else {
                                ForEach(response.interviewReviews) { review in
                                    GuideInterviewReviewCard(review: review)
                                }
                            }
                        } else {
                            if response.workReviews.isEmpty {
                                EmptyStateView(title: guideText(language, "还没有工作评价", "仕事レビューはまだありません", "No work reviews yet"), subtitle: guideText(language, "所有评论审核通过后才会展示。", "レビューは審査通過後に表示されます。", "Reviews appear after moderation."), systemImage: "person.text.rectangle")
                            } else {
                                ForEach(response.workReviews) { review in
                                    GuideWorkReviewCard(review: review)
                                }
                            }
                        }
                        GuideNotePanel(text: response.disclaimer)
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            } else {
                EmptyStateView(title: guideText(language, "评论不存在", "レビューが見つかりません", "Review not found"), subtitle: guideText(language, "它可能已被移动或下线。", "移動または非公開になった可能性があります。", "It may have been moved or unpublished."), systemImage: "bubble.left")
            }
        }
        .navigationTitle(guideText(language, "公司评论", "会社レビュー", "Company reviews"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(country):\(companyId)") { await load() }
        .sheet(isPresented: $isShowingComposer) {
            GuideSubmitReviewView(companyId: companyId, defaultTab: selectedTab) {
                isShowingComposer = false
                Task { await load() }
            }
            .presentationDetents([.large])
        }
    }

    private func count(for tab: ReviewTab, response: KaiXGuideCompanyReviewsResponse) -> Int {
        tab == .interview ? response.interviewReviews.count : response.workReviews.count
    }

    private func load() async {
        guard country == "jp" else {
            isLoading = false
            response = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            response = try await KaiXAPIClient.shared.guideCompanyReviews(companyId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuideInterviewReviewListView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var reviews: [KaiXGuideInterviewReviewDTO] = []
    @State private var city = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach([("", guideText(language, "全部地区", "すべての地域", "All areas")), ("tokyo", "Tokyo"), ("osaka", "Osaka")], id: \.0) { value, title in
                                    GuidePillButton(title: title, isSelected: city == value) {
                                        city = value
                                    }
                                }
                            }
                        }
                        if isLoading {
                            LoadingView()
                        } else if let errorMessage {
                            ErrorStateView(message: errorMessage) {
                                Task { await load() }
                            }
                        } else if reviews.isEmpty {
                            EmptyStateView(title: guideText(language, "还没有面试评论", "面接レビューはまだありません", "No interview reviews yet"), subtitle: guideText(language, "真实用户提交并审核后会展示在这里。", "実ユーザーの投稿が審査後にここへ表示されます。", "Real user submissions appear here after moderation."), systemImage: "bubble.left.and.bubble.right")
                        } else {
                            ForEach(reviews) { review in
                                GuideInterviewReviewCard(review: review)
                            }
                        }
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            }
        }
        .navigationTitle(guideText(language, "面试评论", "面接レビュー", "Interview reviews"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: city) { await load() }
    }

    private func load() async {
        guard country == "jp" else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await KaiXAPIClient.shared.guideInterviewReviews(
                country: country,
                city: city.isEmpty ? nil : city,
                pageSize: 50
            )
            reviews = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuideSubmitReviewView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var tab: GuideCompanyReviewsView.ReviewTab
    @State private var position = ""
    @State private var employmentType = "正社员"
    @State private var pros = ""
    @State private var cons = ""
    @State private var overtimeLevel = ""
    @State private var foreignerSupport = ""
    @State private var salaryBenefits = ""
    @State private var careerGrowth = ""
    @State private var recommendationScore = 4.0
    @State private var interviewRounds = 2
    @State private var interviewLanguage = "日语"
    @State private var difficulty = "普通"
    @State private var questions = ""
    @State private var processDescription = ""
    @State private var result = "等待结果"
    @State private var interviewYear = Calendar.current.component(.year, from: Date())
    @State private var city = "tokyo"
    @State private var isSubmitting = false
    @State private var message: String?

    let companyId: String
    let onSubmitted: () -> Void

    init(companyId: String, defaultTab: GuideCompanyReviewsView.ReviewTab, onSubmitted: @escaping () -> Void) {
        self.companyId = companyId
        self.onSubmitted = onSubmitted
        _tab = State(initialValue: defaultTab)
    }

    private var canSubmit: Bool {
        let hasPosition = !position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if tab == .interview {
            return hasPosition && (!questions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !processDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        return hasPosition && (!pros.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !cons.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(guideText(language, "类型", "種別", "Type"), selection: $tab) {
                        ForEach(GuideCompanyReviewsView.ReviewTab.allCases) { tab in
                            Text(tab.title(language)).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField(guideText(language, "岗位/职种", "職種", "Role / position"), text: $position)
                    TextField(guideText(language, "雇佣类型", "雇用形態", "Employment type"), text: $employmentType)
                }

                if tab == .interview {
                    Section(guideText(language, "面试信息", "面接情報", "Interview info")) {
                        Stepper(guideText(language, "面试轮数 \(interviewRounds)", "面接回数 \(interviewRounds)", "Interview rounds \(interviewRounds)"), value: $interviewRounds, in: 0...20)
                        TextField(guideText(language, "面试语言", "面接言語", "Interview language"), text: $interviewLanguage)
                        TextField(guideText(language, "难度", "難易度", "Difficulty"), text: $difficulty)
                        TextField(guideText(language, "结果", "結果", "Result"), text: $result)
                        Stepper(guideText(language, "面试年份 \(interviewYear)", "面接年 \(interviewYear)", "Interview year \(interviewYear)"), value: $interviewYear, in: 2000...2100)
                        TextField(guideText(language, "城市", "都市", "City"), text: $city)
                    }
                    Section(guideText(language, "经验内容", "体験内容", "Experience")) {
                        TextField(guideText(language, "面试问题", "面接質問", "Interview questions"), text: $questions, axis: .vertical)
                            .lineLimit(3...6)
                        TextField(guideText(language, "流程说明", "選考プロセス", "Process description"), text: $processDescription, axis: .vertical)
                            .lineLimit(3...6)
                    }
                } else {
                    Section {
                        TextField(guideText(language, "优点", "良い点", "Pros"), text: $pros, axis: .vertical)
                            .lineLimit(3...6)
                        TextField(guideText(language, "需要留意", "気になる点", "Watch-outs"), text: $cons, axis: .vertical)
                            .lineLimit(3...6)
                        TextField(guideText(language, "加班情况", "残業状況", "Overtime"), text: $overtimeLevel)
                        TextField(guideText(language, "外国人支持", "外国人サポート", "Foreigner support"), text: $foreignerSupport)
                        TextField(guideText(language, "薪资福利", "給与・福利厚生", "Salary and benefits"), text: $salaryBenefits)
                        TextField(guideText(language, "成长空间", "成長機会", "Growth opportunity"), text: $careerGrowth)
                        Slider(value: $recommendationScore, in: 0...5, step: 0.5) {
                            Text(guideText(language, "推荐度", "おすすめ度", "Recommendation"))
                        } minimumValueLabel: {
                            Text("0")
                        } maximumValueLabel: {
                            Text("5")
                        }
                    } header: {
                        Text(guideText(language, "工作评价", "仕事レビュー", "Work review"))
                    } footer: {
                        Text(recommendationScoreText)
                    }
                }

                Section {
                    Text(guideText(language, "默认匿名提交，审核通过后展示。请勿填写个人隐私、联系方式或无法核实的指控。", "デフォルトで匿名投稿され、審査通過後に表示されます。個人情報、連絡先、確認できない告発は書かないでください。", "Submitted anonymously by default and shown after moderation. Do not include private information, contact details, or unverifiable claims."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(guideText(language, "写评论", "レビューを書く", "Write review"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(guideText(language, "取消", "キャンセル", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSubmitting ? guideText(language, "提交中", "送信中", "Submitting") : guideText(language, "提交", "送信", "Submit")) {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
            }
            .alert("Machi Guide", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response: KaiXGuideSubmitResponse
            if tab == .interview {
                response = try await KaiXAPIClient.shared.submitGuideInterviewReview(.init(
                    companyId: companyId,
                    position: position,
                    employmentType: employmentType,
                    interviewRounds: interviewRounds,
                    interviewLanguage: interviewLanguage,
                    difficulty: difficulty,
                    questions: questions,
                    processDescription: processDescription,
                    result: result,
                    interviewYear: interviewYear,
                    city: city,
                    anonymous: true
                ))
            } else {
                response = try await KaiXAPIClient.shared.submitGuideCompanyReview(.init(
                    companyId: companyId,
                    position: position,
                    employmentType: employmentType,
                    pros: pros,
                    cons: cons,
                    overtimeLevel: overtimeLevel,
                    foreignerSupport: foreignerSupport,
                    salaryBenefits: salaryBenefits,
                    careerGrowth: careerGrowth,
                    recommendationScore: recommendationScore,
                    anonymous: true
                ))
            }
            message = response.message
            onSubmitted()
        } catch {
            message = error.localizedDescription
        }
    }

    private var recommendationScoreText: String {
        let score = String(format: "%.1f", recommendationScore)
        return guideText(language, "推荐度 \(score) / 5", "おすすめ度 \(score) / 5", "Recommendation \(score) / 5")
    }
}

