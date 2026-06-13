import SwiftUI

/// Bottom inset for every Guide scroll view so the floating bottom tab bar never
/// covers the last item. Uses the app-wide `chrome.bottomContentPadding` (≈98pt
/// while the tab bar shows; a small value once a detail page hides it) + extra —
/// the same source Home/Discover use, so Guide stops being occluded and stays
/// consistent across iPhone SE / Dynamic Island / Pro Max safe areas.
private struct GuideBottomInset: ViewModifier {
    @EnvironmentObject private var chrome: AppChromeState
    var extra: CGFloat = KXSpacing.xl
    func body(content: Content) -> some View {
        content.padding(.bottom, chrome.bottomContentPadding + extra)
    }
}

private extension View {
    func guideBottomInset(extra: CGFloat = KXSpacing.xl) -> some View {
        modifier(GuideBottomInset(extra: extra))
    }
}

struct GuideHomeView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var regionStore = RegionStore.shared
    @StateObject private var viewModel = GuideViewModel()

    let currentUser: UserEntity

    private var country: String {
        (regionStore.current?.countryCode ?? currentUser.country).lowercased()
    }

    var body: some View {
        ZStack {
            GuideBackground()
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: country) {
            await viewModel.load(country: country)
        }
        .refreshable {
            await viewModel.load(country: country, force: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if country != "jp" {
            GuideComingSoonView()
        } else if viewModel.isLoading && viewModel.home == nil {
            LoadingView()
        } else if let message = viewModel.errorMessage, viewModel.home == nil {
            ErrorStateView(message: message) {
                Task { await viewModel.load(country: country, force: true) }
            }
        } else if viewModel.isComingSoon {
            GuideComingSoonView(empty: viewModel.home?.emptyState)
        } else if let home = viewModel.home {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    GuideHeroSection(home: home, searchText: $viewModel.searchText) { keyword in
                        Task { await viewModel.search(country: country, keyword: keyword) }
                    } onClear: {
                        viewModel.clearSearch()
                    }

                    if let message = viewModel.errorMessage, !message.isEmpty {
                        GuideInlineStatus(message: message)
                    }

                    if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        GuideSearchResultsSection(
                            isSearching: viewModel.isSearching,
                            articles: viewModel.searchResults,
                            schools: viewModel.schoolResults,
                            companies: viewModel.companyResults
                        )
                    } else {
                        GuideCategoryGrid(categories: home.categories)
                        GuideResourceEntriesSection(entries: home.resourceEntries ?? [])
                        // 两个固定大门：会员权益内容 vs 付费商城——所有
                        // 资料/服务都归到这两处，首页其余区块只做发现。
                        GuideDualEntrySection()
                        GuideGoalsSection(goals: home.goals?.title ?? "你现在想做什么？", entries: home.goalEntries)
                        GuideArticleSection(title: "精选指南", subtitle: "由 Machi 编辑部整理", articles: home.featuredArticles)
                        GuideZoneSection(country: country, title: "日本就职专区", subtitle: "就活流程、履历书、面试与公司选择", categoryKey: "career_japan")
                        GuideZoneSection(country: country, title: "日本升学专区", subtitle: "大学院、研究计划书、教授联系与出愿", categoryKey: "study_japan")
                        GuideZoneSection(country: country, title: "语言学校与留学专区", subtitle: "语言学校、签证、入境与费用", categoryKey: "study_abroad_japan")
                        GuideZoneSection(country: country, title: "日语考级专区", subtitle: "JLPT 备考、词汇语法与学习计划", categoryKey: "jlpt")
                        GuideZoneSection(country: country, title: "在日生活专区", subtitle: "役所手续、租房、手机银行卡、医疗与防灾", categoryKey: "life_japan")
                        GuideSchoolsSection(schools: home.featuredSchools ?? [], disclaimer: home.schoolDisclaimer)
                        GuideProductsSection(products: home.featuredProducts + home.featuredServices)
                        GuideCompaniesSection(companies: home.companyHighlights, disclaimer: home.companyDisclaimer ?? home.reviewDisclaimer)
                        GuideArticleSection(title: "最新更新", subtitle: nil, articles: home.latestArticles, compact: true)
                        GuideFAQSection(faq: home.faq)
                    }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, 10)
                .guideBottomInset()
            }
        } else {
            LoadingView()
        }
    }
}

struct GuideCategoryView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var categories: [KaiXGuideCategoryDTO] = []
    @State private var articles: [KaiXGuideArticleDTO] = []
    @State private var products: [KaiXGuideProductDTO] = []
    @State private var selectedSubCategory = ""
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var hasLoadedContent = false
    @State private var errorMessage: String?

    let categoryKey: String

    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }
    private var category: KaiXGuideCategoryDTO? { categories.first { $0.key == categoryKey } }

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else if isLoading && !hasLoadedContent {
                LoadingView()
            } else if let errorMessage, !hasLoadedContent {
                ErrorStateView(message: errorMessage) {
                    Task { await load() }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        categoryHeader
                        subCategoryTabs
                        if isRefreshing {
                            GuideRefreshIndicator()
                        }
                        if let errorMessage, hasLoadedContent {
                            GuideInlineStatus(message: "更新失败：\(errorMessage)")
                        }
                        if !products.isEmpty {
                            GuideProductsSection(
                                products: products,
                                title: categoryKey == "jlpt" ? "JLPT 资料包" : "相关资料与服务",
                                subtitle: categoryKey == "jlpt"
                                    ? "N1-N5 过去问趋势分析与原创练习 · 学习计划"
                                    : "与本频道相关的资料、模板与服务"
                            )
                        }
                        if articles.isEmpty {
                            KXStatePanel(title: "这个分类的指南正在整理中", subtitle: "Machi 编辑部会持续补充内容。", systemImage: "book.closed")
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                                ForEach(articles) { article in
                                    GuideArticleCard(article: article)
                                }
                            }
                        }
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            }
        }
        .navigationTitle(category?.title ?? "日本指南")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(categoryKey):\(selectedSubCategory)") {
            await load()
        }
    }

    private var categoryHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: GuideCopy.symbol(for: category?.icon))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(KXColor.livingAccent)
                    .frame(width: 48, height: 48)
                    .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("MACHI GUIDE")
                        .font(.caption2.weight(.black))
                        .tracking(1.4)
                        .foregroundStyle(KXColor.livingAccent)
                    Text(category?.title ?? "日本指南")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(KXColor.livingInk)
                    Text(category?.subtitle ?? "系统化日本生活与成长指南")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KXColor.livingMuted)
                }
                Spacer(minLength: 0)
            }
            if let description = category?.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(KXColor.livingMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .kxLivingSurface(radius: 24, elevated: true)
    }

    @ViewBuilder
    private var subCategoryTabs: some View {
        let subs = category?.subCategories ?? []
        if !subs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    GuidePillButton(title: "全部", isSelected: selectedSubCategory.isEmpty) {
                        selectedSubCategory = ""
                    }
                    ForEach(subs) { sub in
                        GuidePillButton(title: sub.title, isSelected: selectedSubCategory == sub.key) {
                            selectedSubCategory = sub.key
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func load() async {
        guard country == "jp" else { return }
        let firstLoad = !hasLoadedContent
        if firstLoad {
            isLoading = true
        } else {
            isRefreshing = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isRefreshing = false
        }
        do {
            let categoryData = try await KaiXAPIClient.shared.guideCategories(country: country)
            let articleData = try await KaiXAPIClient.shared.guideArticles(
                country: country,
                categoryKey: categoryKey,
                subCategoryKey: selectedSubCategory.isEmpty ? nil : selectedSubCategory,
                pageSize: 50
            )
            let productData = try await KaiXAPIClient.shared.guideProducts(
                country: country,
                categoryKey: categoryKey,
                pageSize: 20
            )
            categories = categoryData.categories
            articles = articleData.items
            products = productData.items
            hasLoadedContent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GuideRefreshIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            KXSpinner(size: 14, lineWidth: 2)
            Text("正在更新内容")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(KXColor.softBackground.opacity(0.72), in: Capsule())
    }
}

private struct GuideInlineStatus: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(KXColor.heat)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.heat.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct GuideArticleDetailView: View {
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var response: KaiXGuideArticleDetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    let slug: String
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
            } else if let article = response?.article {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        articleHeader(article)
                        articleBody(article)
                        GuideNotePanel(text: "本内容由 \(article.authorName) 整理，仅供参考。涉及签证、入管、考试等官方流程时，请同时以官方最新公告为准。")
                        if let related = response?.related, !related.isEmpty {
                            GuideArticleSection(title: "相关指南", subtitle: nil, articles: related, compact: true)
                        }
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            } else {
                EmptyStateView(title: "指南内容不存在", subtitle: "它可能已被移动或下线。", systemImage: "book.closed")
            }
        }
        .navigationTitle("指南")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(country):\(slug)") { await load() }
    }

    private func articleHeader(_ article: KaiXGuideArticleDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("指南")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(KXColor.accentSoft, in: Capsule())
                Text(article.authorName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(article.title)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: 6) {
                ForEach(article.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(KXColor.softBackground, in: Capsule())
                }
            }
        }
        .padding(18)
        .kxGlassSurface(radius: 24)
    }

    private func articleBody(_ article: KaiXGuideArticleDTO) -> some View {
        let paragraphs = (article.body ?? article.summary)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .kxGlassSurface(radius: 22)
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
            response = try await KaiXAPIClient.shared.guideArticle(slug, country: country)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuideServicesView: View {
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var products: [KaiXGuideProductDTO] = []
    @State private var productType = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }
    private let filters = [
        ("", "全部"),
        ("pdf_material", "PDF 资料"),
        ("template", "模板"),
        ("checklist", "清单"),
        ("resume_review", "履历修改"),
        ("consultation", "咨询"),
    ]

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        servicesHeader
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filters, id: \.0) { value, title in
                                    GuidePillButton(title: title, isSelected: productType == value) {
                                        productType = value
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        if isLoading {
                            LoadingView()
                        } else if let errorMessage {
                            ErrorStateView(message: errorMessage) {
                                Task { await load() }
                            }
                        } else if products.isEmpty {
                            EmptyStateView(title: "暂无相关资料或服务", subtitle: "更多资料正在准备中。", systemImage: "shippingbox")
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                                ForEach(products) { product in
                                    GuideProductCard(product: product)
                                }
                            }
                        }
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            }
        }
        .navigationTitle("资料与服务")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: productType) { await load() }
    }

    private var servicesHeader: some View {
        KXCard(padding: 16, radius: 22) {
            HStack(alignment: .top, spacing: 12) {
                GuideIconBubble(icon: "shippingbox.fill", color: KXColor.heat)
                VStack(alignment: .leading, spacing: 5) {
                    Text("资料与服务")
                        .font(.title2.weight(.bold))
                    Text("资料包、模板、清单、课程与人工辅导服务")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("付费数字资料在 Apple IAP 接入前显示「即将开放」。服务类可先提交预约咨询。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func load() async {
        guard country == "jp" else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await KaiXAPIClient.shared.guideProducts(
                country: country,
                productType: productType.isEmpty ? nil : productType,
                pageSize: 50
            )
            products = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuideMemberResourcesView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var products: [KaiXGuideProductDTO] = []
    @State private var categoryKey = ""
    @State private var keyword = ""
    @State private var membershipActive = false
    @State private var disclaimer = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }
    private let filters = [
        ("", "全部"),
        ("jlpt", "日语"),
        ("study_japan", "升学"),
        ("career_japan", "就职"),
        ("life_japan", "生活"),
        ("study_abroad_japan", "留学"),
        ("guide_services", "模板"),
    ]

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        header
                        filterBar
                        if isLoading {
                            LoadingView()
                        } else if let errorMessage {
                            ErrorStateView(message: errorMessage) {
                                Task { await load() }
                            }
                        } else if products.isEmpty {
                            EmptyStateView(title: "暂无会员资料", subtitle: "更多资料正在整理中。", systemImage: "crown")
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                                ForEach(products) { product in
                                    GuideProductCard(product: product)
                                }
                            }
                        }
                        if !disclaimer.isEmpty {
                            GuideNotePanel(text: disclaimer)
                        }
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            }
        }
        .navigationTitle("会员专属资料")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(categoryKey):\(keyword)") { await load() }
    }

    private var header: some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    GuideIconBubble(icon: "crown.fill", color: KXColor.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("会员专属资料")
                            .font(.title2.weight(.bold))
                        Text("为 Machi 认证会员整理的日本升学、就职、日语和生活资料。")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("服务类不进入会员免费权益；数字内容在 iOS 端遵守 Apple IAP 规则。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !membershipActive {
                    Text("非会员可查看预览，完整内容需开通会员或在 Web 端完成相应购买后同步查看。")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KXColor.accent)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索会员资料", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await load() } }
                }
                .padding(11)
                .background(KXColor.softBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.0) { value, title in
                    GuidePillButton(title: title, isSelected: categoryKey == value) {
                        categoryKey = value
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func load() async {
        guard country == "jp" else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await KaiXAPIClient.shared.guideMemberResources(
                country: country,
                categoryKey: categoryKey.isEmpty ? nil : categoryKey,
                keyword: keyword.isEmpty ? nil : keyword,
                pageSize: 50
            )
            products = response.items
            membershipActive = response.membershipActive ?? false
            disclaimer = response.disclaimer ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuideProductDetailView: View {
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var product: KaiXGuideProductDTO?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    let slug: String
    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else if isLoading {
                LoadingView()
            } else if let errorMessage, product == nil {
                ErrorStateView(message: errorMessage) {
                    Task { await load() }
                }
            } else if let product {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        productHero(product)
                        if product.access?.canAccess == true {
                            purchasedContentPanel(product)
                        } else if let preview = product.previewContent, !preview.isEmpty {
                            previewPanel(preview, locked: product.hasPurchaseContent == true)
                        }
                        productDescription(product)
                        GuideNotePanel(text: "数字资料商品在 Apple IAP 接入前显示「即将开放」。服务类只提交预约咨询，不在 iOS 内提供外部支付按钮。")
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            } else {
                EmptyStateView(title: "资料/服务不存在", subtitle: "它可能已被移动或下线。", systemImage: "shippingbox")
            }
        }
        .navigationTitle("资料与服务")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(country):\(slug)") { await load() }
        .alert("Machi Guide", isPresented: Binding(
            get: { toastMessage != nil },
            set: { if !$0 { toastMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(toastMessage ?? "")
        }
    }

    private func productHero(_ product: KaiXGuideProductDTO) -> some View {
        let price = GuideCopy.productPrice(product)
        return KXCard(padding: 18, radius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 13) {
                    GuideIconBubble(icon: product.isService ? "wrench.and.screwdriver.fill" : "doc.text.fill", color: product.isService ? KXColor.rankTeal : KXColor.heat)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(GuideCopy.productTypeLabel(product.productType))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(product.title)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        if !product.subtitle.isEmpty {
                            Text(product.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Text(price)
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 0)
                    Button {
                        Task { await productAction(product) }
                    } label: {
                        Text(GuideCopy.productCTA(product, busy: isSubmitting, loggedIn: KaiXBackend.token != nil))
                            .font(.subheadline.weight(.bold))
                            .frame(height: 40)
                            .padding(.horizontal, 18)
                            .background(GuideCopy.productActionEnabled(product, busy: isSubmitting) ? KXColor.accent : Color.secondary.opacity(0.20), in: Capsule())
                            .foregroundStyle(GuideCopy.productActionEnabled(product, busy: isSubmitting) ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!GuideCopy.productActionEnabled(product, busy: isSubmitting))
                }
            }
        }
    }

    private func productDescription(_ product: KaiXGuideProductDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !product.description.isEmpty {
                Text(product.description)
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().opacity(0.25)
            if !product.targetAudience.isEmpty {
                GuideMetaRow(title: "适合人群", value: product.targetAudience)
            }
            if !product.deliveryMethod.isEmpty {
                GuideMetaRow(title: "交付方式", value: product.deliveryMethod)
            }
            GuideMetaRow(title: "内容类型", value: product.isService ? "人工服务" : "数字内容")
        }
        .padding(18)
        .kxGlassSurface(radius: 22)
    }

    // Web purchases / membership sync to iOS: when the signed-in account owns the
    // product (or is an active member for a member-included resource), the unified
    // API attaches `purchaseContent` + `fileUrl`, which we show here.
    @ViewBuilder
    private func purchasedContentPanel(_ product: KaiXGuideProductDTO) -> some View {
        KXCard(padding: 18, radius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label(product.access?.memberUnlocked == true ? "会员已解锁" : "已购买", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)
                if let pc = product.purchaseContent, !pc.isEmpty {
                    Text(pc)
                        .font(.callout)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let f = product.fileUrl, !f.isEmpty, let url = URL(string: f) {
                    Link(destination: url) {
                        Label("下载资料", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func previewPanel(_ preview: String, locked: Bool) -> some View {
        KXCard(padding: 18, radius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Label("预览内容", systemImage: "lock.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if locked {
                    Text("完整内容请在 Web 端购买或开通会员后，于 iOS 登录同一账号查看。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func productAction(_ product: KaiXGuideProductDTO) async {
        guard GuideCopy.productActionEnabled(product, busy: isSubmitting) else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response: KaiXGuideSubmitResponse
            if product.isService {
                response = try await KaiXAPIClient.shared.submitGuideServiceRequest(.init(
                    productId: product.slug,
                    serviceType: product.productType,
                    contactMethod: "app",
                    message: "我想预约：\(product.title)"
                ))
            } else {
                response = try await KaiXAPIClient.shared.purchaseGuideProduct(product.slug)
            }
            toastMessage = response.message
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    private func load() async {
        guard country == "jp" else {
            isLoading = false
            product = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await KaiXAPIClient.shared.guideProduct(slug, country: country)
            product = response.product
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuideSchoolListView: View {
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
                            EmptyStateView(title: "暂无匹配学校", subtitle: "试试其他学校类型、地区或关键词。", systemImage: "graduationcap")
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
        .navigationTitle("日本学校库")
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
                        Text("日本学校库")
                            .font(.title3.weight(.bold))
                        Text("大学、大学院、专门学校与语言学校的官方入口")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索学校名、学科、城市", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await load() } }
                    Button("搜索") {
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
                    ForEach([("", "全部"), ("university", "大学"), ("graduate_school", "大学院"), ("vocational_school", "专门学校"), ("language_school", "语言学校")], id: \.0) { value, title in
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
                        GuidePillButton(title: "首都圈", isSelected: regionGroup == "capital_area") {
                            regionGroup = regionGroup == "capital_area" ? "" : "capital_area"
                        }
                        GuidePillButton(title: "关西圈", isSelected: regionGroup == "kansai_area") {
                            regionGroup = regionGroup == "kansai_area" ? "" : "kansai_area"
                        }
                        GuidePillButton(title: "留学生可申请", isSelected: supportFilter == "international") {
                            supportFilter = supportFilter == "international" ? "" : "international"
                        }
                        GuidePillButton(title: "英文项目", isSelected: supportFilter == "english") {
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
                        Text(activeFilterCount > 0 ? "筛选 \(activeFilterCount)" : "筛选")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(activeFilterCount > 0 ? Color.white : KXColor.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(activeFilterCount > 0 ? KXColor.accent : KXColor.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuideCompanyListView: View {
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
                            EmptyStateView(title: "暂无匹配公司", subtitle: "试试其他关键词、地区或放宽筛选。", systemImage: "building.2")
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
        .navigationTitle("外国人就职公司库")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: [regionGroup, industry, city, companySize, employmentType, supportFilter, sort].joined(separator: ":")) { await load() }
    }

    private var companySearchHeader: some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    GuideIconBubble(icon: "building.2.fill", color: KXColor.rankTeal)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("外国人就职公司库")
                            .font(.title3.weight(.bold))
                        Text("以官方招聘页、签证支持和真实评价为主")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索公司名、行业、岗位", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await load() } }
                    Button("搜索") {
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
                    ForEach([("", "全部地区"), ("tokyo", "东京"), ("yokohama", "横滨"), ("osaka", "大阪"), ("kyoto", "京都"), ("kobe", "神户")], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: city == value) {
                            city = value
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([("", "日本全国"), ("capital_area", "首都圈"), ("kansai_area", "关西圈")], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: regionGroup == value) {
                            regionGroup = value
                        }
                    }
                    ForEach([("", "全部行业"), ("it_internet", "IT"), ("software", "软件"), ("ai_data", "AI/Data"), ("manufacturing", "制造"), ("finance", "金融"), ("consulting", "咨询"), ("game_entertainment", "游戏")], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: industry == value) {
                            industry = value
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([("", "全部规模"), ("enterprise", "大手"), ("large", "大型"), ("medium", "中型"), ("startup", "初创")], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: companySize == value) {
                            companySize = value
                        }
                    }
                    ForEach([("", "全部雇佣"), ("new_graduate", "新卒"), ("mid_career", "中途"), ("internship", "实习"), ("global_hire", "Global hire")], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: employmentType == value) {
                            employmentType = value
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([("visa", "签证支持"), ("foreign", "外国人友好"), ("english", "英文岗位"), ("global", "Global career"), ("employees", "外国员工")], id: \.0) { value, title in
                        GuidePillButton(title: title, isSelected: supportFilter == value) {
                            supportFilter = supportFilter == value ? "" : value
                        }
                    }
                    ForEach([("recommended", "推荐"), ("data_quality", "完整度"), ("recently_updated", "最近更新"), ("review_count", "评论数"), ("name_jp_asc", "日文名")], id: \.0) { value, title in
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuideSchoolDetailView: View {
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
                            GuideArticleSection(title: "相关指南", subtitle: nil, articles: response.relatedArticles, compact: true)
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
                EmptyStateView(title: "学校不存在", subtitle: "它可能已被移动或下线。", systemImage: "graduationcap")
            }
        }
        .navigationTitle("学校详情")
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
                            GuideCopy.schoolTypeLabel(school.schoolType),
                            GuideCopy.cityLabel(school.city),
                            school.prefecture.isEmpty ? "" : school.prefecture,
                            school.ward ?? ""
                        ].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    GuideBadge(GuideCopy.sourceStatusLabel(school.verificationStatus), tint: KXColor.rankSky)
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
                            Label("学校官网", systemImage: "link")
                        }
                    }
                    if let url = GuideCopy.url(school.internationalAdmissionUrl) {
                        Link(destination: url) {
                            Label("国际招生/入试页面", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    if let url = GuideCopy.url(school.applicationUrl) {
                        Link(destination: url) {
                            Label("申请入口", systemImage: "square.and.pencil")
                        }
                    }
                    if let url = GuideCopy.url(school.scholarshipUrl) {
                        Link(destination: url) {
                            Label("奖学金页面", systemImage: "yensign.circle.fill")
                        }
                    }
                    if let url = GuideCopy.url(school.careerSupportUrl) {
                        Link(destination: url) {
                            Label("就职支持", systemImage: "briefcase.fill")
                        }
                    }
                    if let url = GuideCopy.url(school.dormitoryUrl) {
                        Link(destination: url) {
                            Label("宿舍信息", systemImage: "house.fill")
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
                Text("申请信息")
                    .font(.headline.weight(.bold))
                GuideMetaRow(title: "地址", value: [school.postalCode ?? "", school.prefecture, school.city, school.ward ?? "", school.address ?? ""].filter { !$0.isEmpty }.joined(separator: " ").ifEmpty("待补充"))
                GuideMetaRow(title: "学费", value: GuideCopy.moneyRange(min: school.tuitionMin, max: school.tuitionMax, currency: school.currency))
                GuideMetaRow(title: "入学月份", value: GuideCopy.joinedOrPending(school.admissionMonths))
                GuideMetaRow(title: "日语要求", value: GuideCopy.levelLabel(school.requiredJapaneseLevel))
                GuideMetaRow(title: "英语要求", value: GuideCopy.levelLabel(school.requiredEnglishLevel))
                GuideMetaRow(title: "考试要求", value: "JLPT \(GuideCopy.levelLabel(school.jlptRequired ?? "unknown")) · EJU \(GuideCopy.levelLabel(school.ejuRequired ?? "unknown")) · TOEFL \(GuideCopy.levelLabel(school.toeflRequired ?? "unknown")) · IELTS \(GuideCopy.levelLabel(school.ieltsRequired ?? "unknown"))")
                GuideMetaRow(title: "学部/研究科", value: [
                    GuideCopy.joinedOrPending(school.faculties ?? []),
                    GuideCopy.joinedOrPending(school.graduateSchools ?? []),
                    GuideCopy.joinedOrPending(school.departments ?? []),
                ].filter { $0 != "待补充" }.joined(separator: " / ").ifEmpty("待补充"))
                GuideMetaRow(title: "数据完整度", value: "\(school.dataQualityScore ?? 0) / 100")
                GuideMetaRow(title: "数据来源", value: [school.sourceName ?? "", school.sourceLastCheckedAt ?? "", GuideCopy.sourceStatusLabel(school.verificationStatus)].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty("待核验"))
                FlowLayout(spacing: 6) {
                    GuideBadge(GuideCopy.triStateLabel(school.isAcceptingInternationalStudents, trueText: "接受留学生"), tint: KXColor.rankSky)
                    GuideBadge(GuideCopy.triStateLabel(school.hasEnglishProgram, trueText: "英文项目"), tint: KXColor.rankTeal)
                    GuideBadge(GuideCopy.triStateLabel(school.hasJapaneseProgram, trueText: "日语项目"), tint: KXColor.rankTeal)
                    GuideBadge(GuideCopy.triStateLabel(school.hasScholarship, trueText: "奖学金"), tint: KXColor.rankGold)
                    GuideBadge(GuideCopy.triStateLabel(school.hasDormitory, trueText: "宿舍"), tint: KXColor.rankViolet)
                    GuideBadge(GuideCopy.triStateLabel(school.hasCareerSupport, trueText: "就业支持"), tint: KXColor.accent)
                    GuideBadge(GuideCopy.triStateLabel(school.hasLanguageSupport, trueText: "语言支持"), tint: KXColor.rankSky)
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
                    Label(isSubmitting ? "处理中" : "收藏学校", systemImage: "bookmark.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(KXColor.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)

                TextField("发现官网、招生信息有误？在这里提交纠错", text: $correctionText, axis: .vertical)
                    .font(.footnote)
                    .lineLimit(2...4)
                    .padding(11)
                    .background(KXColor.softBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Button("提交纠错") {
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
            GuideSectionHeader(title: "项目与课程", subtitle: "只展示后台录入或官方来源补充的内容")
            if programs.isEmpty {
                KXStatePanel(title: "项目资料待补充", subtitle: "当前学校还没有录入具体项目。", systemImage: "list.bullet.rectangle")
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
                                GuideBadge(GuideCopy.levelLabel(program.degreeLevel), tint: KXColor.rankSky)
                                if !program.field.isEmpty { GuideBadge(program.field) }
                                if !program.languageOfInstruction.isEmpty { GuideBadge(program.languageOfInstruction, tint: KXColor.rankTeal) }
                                if program.durationMonths > 0 { GuideBadge("\(program.durationMonths) 个月") }
                            }
                            if !program.description.isEmpty {
                                Text(program.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let url = GuideCopy.url(program.applicationUrl) {
                                Link("项目申请页面", destination: url)
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
            GuideSectionHeader(title: "出愿与入试", subtitle: "申请材料、选考方式和奖学金信息")
            if admissions.isEmpty {
                KXStatePanel(title: "出愿资料待补充", subtitle: "请以学校官方招生页面为准。", systemImage: "doc.text")
            } else {
                ForEach(admissions) { admission in
                    KXCard(padding: 14, radius: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(admission.admissionType.isEmpty ? "入试信息" : admission.admissionType)
                                    .font(.headline.weight(.bold))
                                Spacer(minLength: 0)
                                if !admission.enrollmentMonth.isEmpty {
                                    GuideBadge(admission.enrollmentMonth, tint: KXColor.rankSky)
                                }
                            }
                            if !admission.selectionMethod.isEmpty {
                                GuideMetaRow(title: "选考", value: admission.selectionMethod)
                            }
                            if !admission.requiredDocuments.isEmpty {
                                GuideMetaRow(title: "材料", value: admission.requiredDocuments.joined(separator: "、"))
                            }
                            if !admission.scholarshipInfo.isEmpty {
                                GuideMetaRow(title: "奖学金", value: admission.scholarshipInfo)
                            }
                            if !admission.notes.isEmpty {
                                Text(admission.notes)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let url = GuideCopy.url(admission.sourceUrl) {
                                Link("官方来源", destination: url)
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
            toastMessage = "已收藏学校"
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
                                Text("查看评论（面试 \(response.interviewReviewCount) · 工作 \(response.workReviewCount)）")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(KXColor.accent, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        if let related = response.relatedArticles, !related.isEmpty {
                            GuideArticleSection(title: "相关指南", subtitle: nil, articles: related, compact: true)
                        }
                        GuideNotePanel(text: response.disclaimer)
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            } else {
                EmptyStateView(title: "公司不存在", subtitle: "它可能已被移动或下线。", systemImage: "building.2")
            }
        }
        .navigationTitle("公司详情")
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
                        Text([company.industry, company.subIndustry ?? "", company.prefecture ?? "", GuideCopy.cityLabel(company.city), company.ward ?? "", company.size].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let status = company.verificationStatus, !status.isEmpty {
                        GuideBadge(GuideCopy.sourceStatusLabel(status), tint: KXColor.rankTeal)
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
                        GuideBadge("日语 \(GuideCopy.levelLabel(level))", tint: KXColor.rankSky)
                    }
                    if let level = company.requiredEnglishLevel, !level.isEmpty {
                        GuideBadge("英语 \(GuideCopy.levelLabel(level))", tint: KXColor.rankTeal)
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
                            Label("公司官网", systemImage: "link")
                        }
                    }
                    if let url = GuideCopy.url(company.careerUrl) {
                        Link(destination: url) {
                            Label("官方招聘页", systemImage: "briefcase.fill")
                        }
                    }
                    if let url = GuideCopy.url(company.newGraduateUrl) {
                        Link(destination: url) {
                            Label("新卒採用", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    if let url = GuideCopy.url(company.midCareerUrl) {
                        Link(destination: url) {
                            Label("中途採用", systemImage: "person.text.rectangle")
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
                    Label(isSubmitting ? "处理中" : "收藏公司", systemImage: "bookmark.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(KXColor.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)

                TextField("发现招聘页、签证信息有误？在这里提交纠错", text: $correctionText, axis: .vertical)
                    .font(.footnote)
                    .lineLimit(2...4)
                    .padding(11)
                    .background(KXColor.softBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Button("提交纠错") {
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
                Text("就职信号")
                    .font(.headline.weight(.bold))
                GuideMetaRow(title: "行业", value: [company.industry, company.subIndustry ?? "", company.companySize ?? company.size].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty("待补充"))
                GuideMetaRow(title: "地区", value: [company.prefecture ?? "", GuideCopy.cityLabel(company.city), company.ward ?? ""].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty("待补充"))
                GuideMetaRow(title: "地址", value: [company.postalCode ?? "", company.prefecture ?? "", company.city, company.ward ?? "", company.address ?? ""].filter { !$0.isEmpty }.joined(separator: " ").ifEmpty("待补充"))
                GuideMetaRow(title: "法人番号", value: company.corporateNumber?.isEmpty == false ? company.corporateNumber! : "待补充")
                GuideMetaRow(title: "雇佣类型", value: GuideCopy.joinedOrPending(company.employmentTypes ?? []))
                GuideMetaRow(title: "语言要求", value: "日语 \(GuideCopy.levelLabel(company.requiredJapaneseLevel ?? "unknown")) · 英语 \(GuideCopy.levelLabel(company.requiredEnglishLevel ?? "unknown"))")
                GuideMetaRow(title: "数据完整度", value: "\(company.dataQualityScore ?? 0) / 100")
                GuideMetaRow(title: "数据来源", value: [company.sourceName ?? "", company.sourceLastCheckedAt ?? "", GuideCopy.sourceStatusLabel(company.verificationStatus ?? "")].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty("待核验"))
                FlowLayout(spacing: 6) {
                    GuideBadge(GuideCopy.triStateLabel(company.acceptsForeignApplicants, trueText: "接受外国人申请"), tint: KXColor.rankTeal)
                    GuideBadge(GuideCopy.triStateLabel(company.supportsWorkVisa, trueText: "签证支持"), tint: KXColor.accent)
                    GuideBadge(GuideCopy.triStateLabel(company.supportsNewGraduate, trueText: "新卒"), tint: KXColor.rankGold)
                    GuideBadge(GuideCopy.triStateLabel(company.supportsMidCareer, trueText: "中途"), tint: KXColor.rankGold)
                    GuideBadge(GuideCopy.triStateLabel(company.hasEnglishPositions, trueText: "英文岗位"), tint: KXColor.rankSky)
                    GuideBadge(GuideCopy.triStateLabel(company.hasGlobalRoles, trueText: "Global career"), tint: KXColor.rankSky)
                    GuideBadge(GuideCopy.triStateLabel(company.hasForeignEmployees, trueText: "有外国籍员工"), tint: KXColor.rankViolet)
                }
            }
        }
    }

    private func positionSection(_ positions: [KaiXGuideCompanyPositionDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideSectionHeader(title: "公开岗位", subtitle: "来自后台录入或官方招聘页，薪资与条件以官方页面为准")
            if positions.isEmpty {
                KXStatePanel(title: "岗位资料待补充", subtitle: "请优先查看公司官方招聘页。", systemImage: "briefcase")
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
                    Text("真实评价")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text(company.reviewCount > 0 ? "\(company.reviewCount) 条评价" : "暂无评价")
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
                        GuideScoreRow(title: "签证支持", value: value)
                    }
                    if let value = scores.careerGrowth {
                        GuideScoreRow(title: "成长空间", value: value)
                    }
                } else {
                    Text("暂无足够真实评价数据。评分将在用户提交并通过审核后显示，我们不预设主观分数。")
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
        var title: String { self == .interview ? "面试评论" : "工作评价" }
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
                                GuidePillButton(title: "\(tab.title) \(count(for: tab, response: response))", isSelected: selectedTab == tab) {
                                    selectedTab = tab
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        Button {
                            isShowingComposer = true
                        } label: {
                            Label("写评论", systemImage: "square.and.pencil")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(KXColor.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        if selectedTab == .interview {
                            if response.interviewReviews.isEmpty {
                                EmptyStateView(title: "还没有面试评论", subtitle: "到这里分享第一条真实面试经验。", systemImage: "bubble.left.and.bubble.right")
                            } else {
                                ForEach(response.interviewReviews) { review in
                                    GuideInterviewReviewCard(review: review)
                                }
                            }
                        } else {
                            if response.workReviews.isEmpty {
                                EmptyStateView(title: "还没有工作评价", subtitle: "所有评论审核通过后才会展示。", systemImage: "person.text.rectangle")
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
                EmptyStateView(title: "评论不存在", subtitle: "它可能已被移动或下线。", systemImage: "bubble.left")
            }
        }
        .navigationTitle("公司评论")
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
                                ForEach([("", "全部地区"), ("tokyo", "东京"), ("osaka", "大阪")], id: \.0) { value, title in
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
                            EmptyStateView(title: "还没有面试评论", subtitle: "真实用户提交并审核后会展示在这里。", systemImage: "bubble.left.and.bubble.right")
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
        .navigationTitle("面试评论")
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
                    Picker("类型", selection: $tab) {
                        ForEach(GuideCompanyReviewsView.ReviewTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("岗位/职种", text: $position)
                    TextField("雇佣类型", text: $employmentType)
                }

                if tab == .interview {
                    Section("面试信息") {
                        Stepper("面试轮数 \(interviewRounds)", value: $interviewRounds, in: 0...20)
                        TextField("面试语言", text: $interviewLanguage)
                        TextField("难度", text: $difficulty)
                        TextField("结果", text: $result)
                        Stepper("面试年份 \(interviewYear)", value: $interviewYear, in: 2000...2100)
                        TextField("城市", text: $city)
                    }
                    Section("经验内容") {
                        TextField("面试问题", text: $questions, axis: .vertical)
                            .lineLimit(3...6)
                        TextField("流程说明", text: $processDescription, axis: .vertical)
                            .lineLimit(3...6)
                    }
                } else {
                    Section {
                        TextField("优点", text: $pros, axis: .vertical)
                            .lineLimit(3...6)
                        TextField("需要留意", text: $cons, axis: .vertical)
                            .lineLimit(3...6)
                        TextField("加班情况", text: $overtimeLevel)
                        TextField("外国人支持", text: $foreignerSupport)
                        TextField("薪资福利", text: $salaryBenefits)
                        TextField("成长空间", text: $careerGrowth)
                        Slider(value: $recommendationScore, in: 0...5, step: 0.5) {
                            Text("推荐度")
                        } minimumValueLabel: {
                            Text("0")
                        } maximumValueLabel: {
                            Text("5")
                        }
                    } header: {
                        Text("工作评价")
                    } footer: {
                        Text("推荐度 \(recommendationScore, specifier: "%.1f") / 5")
                    }
                }

                Section {
                    Text("默认匿名提交，审核通过后展示。请勿填写个人隐私、联系方式或无法核实的指控。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("写评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSubmitting ? "提交中" : "提交") {
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
}

struct GuideComingSoonView: View {
    @ObservedObject private var regionStore = RegionStore.shared
    var empty: KaiXGuideEmptyStateDTO?

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            GuideIconBubble(icon: "airplane.departure", color: KXColor.rankSky, size: 68)
            Text(empty?.title ?? "Machi 指南目前只开放日本地区")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(empty?.body ?? "如果你正在准备日本留学、升学、就职，或在备考日语（JLPT）、了解在日生活，切换到日本地区即可查看完整的指南、学校库、公司库与资料服务。其他国家和地区将陆续开放。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 26)
            Button {
                _ = regionStore.setCurrent(country: "jp", province: "tokyo", city: "tokyo")
            } label: {
                Text(empty?.action ?? "切换到日本地区")
                    .font(.subheadline.weight(.bold))
                    .frame(height: 44)
                    .padding(.horizontal, 22)
                    .background(KXColor.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 80)
        }
        .padding()
    }
}

private struct GuideSchoolFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var schoolType: String
    @Binding var regionGroup: String
    @Binding var prefecture: String
    @Binding var field: String
    @Binding var supportFilter: String
    @Binding var sort: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    group("学校类型", options: [("", "全部"), ("university", "大学"), ("graduate_school", "大学院"), ("junior_college", "短大"), ("college_of_technology", "高专"), ("vocational_school", "专门学校"), ("language_school", "语言学校")], selection: $schoolType, toggle: false)
                    group("圈域", options: [("capital_area", "首都圈"), ("kansai_area", "关西圈")], selection: $regionGroup, toggle: true)
                    group("都道府县", options: [("", "全部"), ("tokyo", "东京"), ("kanagawa", "神奈川"), ("chiba", "千叶"), ("saitama", "埼玉"), ("kyoto", "京都"), ("osaka", "大阪"), ("hyogo", "兵库")], selection: $prefecture, toggle: false)
                    group("专业领域", options: [("", "全部"), ("engineering", "工学"), ("business", "经营"), ("it", "IT"), ("language", "语言"), ("design", "设计")], selection: $field, toggle: false)
                    group("支持条件", options: [("international", "留学生可申请"), ("english", "英文项目"), ("japanese", "日语项目"), ("scholarship", "奖学金"), ("dormitory", "宿舍"), ("career", "就职支持"), ("language_support", "语言支持")], selection: $supportFilter, toggle: true)
                    group("排序", options: [("recommended", "推荐"), ("data_quality", "完整度"), ("recently_updated", "最近更新"), ("popular", "人气"), ("name_jp_asc", "日文名")], selection: $sort, toggle: false)
                }
                .padding(KXSpacing.screen)
            }
            .navigationTitle("筛选学校")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重置") {
                        schoolType = ""; regionGroup = ""; prefecture = ""; field = ""; supportFilter = ""; sort = "recommended"
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("应用") { dismiss() }.fontWeight(.bold)
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, options: [(String, String)], selection: Binding<String>, toggle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.subheadline.weight(.bold))
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.0) { value, label in
                    GuidePillButton(title: label, isSelected: selection.wrappedValue == value) {
                        if toggle {
                            selection.wrappedValue = (selection.wrappedValue == value) ? "" : value
                        } else {
                            selection.wrappedValue = value
                        }
                    }
                }
            }
        }
    }
}

private struct GuideHeroSection: View {
    let home: KaiXGuideHomeResponse
    @Binding var searchText: String
    let onSearch: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "book.pages")
                Text("Machi Guide · 日本指南")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(KXColor.livingAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(KXColor.livingAccentSoft, in: Capsule())

            Text(home.hero.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(KXColor.livingInk)
            Text(home.hero.subtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KXColor.livingMuted)
            Text(home.hero.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(KXColor.livingAccent)
                TextField(home.hero.searchPlaceholder, text: $searchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { onSearch(searchText) }
                if searchText.isEmpty {
                    Button("搜索") { onSearch(searchText) }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(KXColor.livingAccent)
                } else {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(KXColor.livingInk.opacity(0.08), lineWidth: 0.8)
            }

            FlowLayout(spacing: 7) {
                ForEach(home.hero.quickTags, id: \.self) { tag in
                    Button {
                        searchText = tag
                        onSearch(tag)
                    } label: {
                        Text(tag)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.78))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(KXColor.livingSurface.opacity(0.82), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(15)
        .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(KXColor.livingInk.opacity(0.06), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
    }
}

private struct GuideSearchResultsSection: View {
    let isSearching: Bool
    let articles: [KaiXGuideArticleDTO]
    let schools: [KaiXGuideSchoolDTO]
    let companies: [KaiXGuideCompanyDTO]

    private var total: Int { articles.count + schools.count + companies.count }

    var body: some View {
        GuideSectionHeader(
            title: "搜索结果",
            subtitle: isSearching ? "正在查找学校、公司和指南" : "共 \(total) 条 · 学校 / 公司 / 指南都已包含"
        )
        if isSearching {
            LoadingView()
        } else if total == 0 {
            EmptyStateView(title: "没有找到相关内容", subtitle: "换个关键词试试，可以搜学校、公司名和任意指南内容。", systemImage: "magnifyingglass")
        } else {
            if !schools.isEmpty {
                groupLabel(icon: "graduationcap.fill", title: "学校", count: schools.count)
                ForEach(schools) { GuideSchoolCard(school: $0) }
            }
            if !companies.isEmpty {
                groupLabel(icon: "building.2.fill", title: "就职公司", count: companies.count)
                ForEach(companies) { GuideCompanyCard(company: $0) }
            }
            if !articles.isEmpty {
                groupLabel(icon: "doc.text.fill", title: "指南文章", count: articles.count)
                ForEach(articles) { GuideArticleCard(article: $0, compact: true) }
            }
        }
    }

    private func groupLabel(icon: String, title: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.livingAccent)
            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(KXColor.livingInk)
            Text("\(count)")
                .font(.caption2.weight(.black))
                .foregroundStyle(KXColor.livingAccent)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(KXColor.livingAccentSoft, in: Capsule())
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}

private struct GuideCategoryGrid: View {
    let categories: [KaiXGuideCategoryDTO]

    var body: some View {
        if !categories.isEmpty {
            GuideSectionHeader(title: "核心分类", subtitle: "升学、就职、留学、日语、生活与核心资料库")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(categories) { category in
                    GuideCategoryCard(category: category)
                }
            }
        }
    }
}

private struct GuideResourceEntriesSection: View {
    @EnvironmentObject private var router: AppRouter
    let entries: [KaiXGuideResourceEntryDTO]

    var body: some View {
        if !entries.isEmpty {
            GuideSectionHeader(title: "核心资料库", subtitle: "学校与就职公司信息以官方来源和后台审核为准")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(entries) { entry in
                    Button {
                        open(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            GuideIconBubble(
                                icon: GuideCopy.resourceSymbol(entry.icon),
                                color: GuideCopy.resourceColor(entry.key),
                                size: 44
                            )
                            Text(entry.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(entry.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            HStack(spacing: 4) {
                                Text("进入资料库")
                                Image(systemName: "arrow.right")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                        }
                        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
                        .padding(14)
                        .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
                        .shadow(color: Color.black.opacity(0.035), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func open(_ entry: KaiXGuideResourceEntryDTO) {
        switch entry.key {
        case "japan_schools":
            router.open(.guideSchools)
        case "foreigner_friendly_companies":
            router.open(.guideCompanies)
        default:
            if entry.href.contains("schools") {
                router.open(.guideSchools)
            } else if entry.href.contains("companies") {
                router.open(.guideCompanies)
            }
        }
    }
}

private struct GuideGoalsSection: View {
    @EnvironmentObject private var router: AppRouter
    let goals: String
    let entries: [KaiXGuideGoalEntryDTO]

    var body: some View {
        if !entries.isEmpty {
            GuideSectionHeader(title: goals, subtitle: "按你的目标快速进入")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entries) { entry in
                        Button {
                            router.open(.guideCategory(categoryKey: entry.categoryKey))
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(KXColor.accent)
                                Text(entry.title)
                                    .lineLimit(1)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(KXColor.cardBackground, in: Capsule())
                            .overlay(Capsule().stroke(KXColor.separator, lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct GuideArticleSection: View {
    let title: String
    let subtitle: String?
    let articles: [KaiXGuideArticleDTO]
    var compact = false

    var body: some View {
        if !articles.isEmpty {
            GuideSectionHeader(title: title, subtitle: subtitle)
            ForEach(articles) { article in
                GuideArticleCard(article: article, compact: compact)
            }
        }
    }
}

private struct GuideZoneSection: View {
    @State private var articles: [KaiXGuideArticleDTO] = []
    @State private var didLoad = false

    let country: String
    let title: String
    let subtitle: String
    let categoryKey: String

    var body: some View {
        Group {
            if !didLoad || !articles.isEmpty {
                GuideSectionHeader(title: title, subtitle: subtitle)
                if didLoad {
                    ForEach(articles) { article in
                        GuideArticleCard(article: article, compact: true)
                    }
                } else {
                    LoadingView()
                }
            }
        }
        .task(id: country + categoryKey) {
            guard country == "jp" else { return }
            do {
                let response = try await KaiXAPIClient.shared.guideArticles(country: country, categoryKey: categoryKey, pageSize: 3)
                articles = response.items
            } catch {
                articles = []
            }
            didLoad = true
        }
    }
}

private struct GuideProductsSection: View {
    @EnvironmentObject private var router: AppRouter
    let products: [KaiXGuideProductDTO]
    var title: String = "资料与服务"
    var subtitle: String = "资料包、模板、清单与人工辅导"

    var body: some View {
        if !products.isEmpty {
            HStack {
                GuideSectionHeader(title: title, subtitle: subtitle)
                Spacer()
                Button("查看全部") {
                    router.open(.guideServices)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(products) { product in
                        GuideProductCard(product: product)
                            .frame(width: 236)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// The two permanent doors of the Guide tab: everything entitled by the
/// membership lives behind 会员专区, while templates and human help live behind
/// 资料与服务. Side-by-side tiles so the split is legible at a glance.
private struct GuideDualEntrySection: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideSectionHeader(title: "会员与商城", subtitle: "会员专属资料、原创资料包、模板与人工服务统一入口")
            HStack(spacing: 10) {
                entryTile(
                    icon: "crown.fill",
                    tint: KXColor.accent,
                    title: "会员专区",
                    subtitle: "清单模板资料\n会员权益内容"
                ) {
                    router.open(.guideMemberResources)
                }
                entryTile(
                    icon: "bag.fill",
                    tint: .orange,
                    title: "资料商城",
                    subtitle: "资料包与人工服务\n按需购买预约"
                ) {
                    router.open(.guideServices)
                }
            }
        }
    }

    private func entryTile(icon: String, tint: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    GuideIconBubble(icon: icon, color: tint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxGlassSurface(radius: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct GuideSchoolsSection: View {
    @EnvironmentObject private var router: AppRouter
    let schools: [KaiXGuideSchoolDTO]
    let disclaimer: String?

    var body: some View {
        if !schools.isEmpty {
            HStack {
                GuideSectionHeader(title: "日本学校库", subtitle: "大学、大学院、专门学校、语言学校")
                Spacer()
                Button("查看全部") {
                    router.open(.guideSchools)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.accent)
            }
            ForEach(schools.prefix(4)) { school in
                GuideSchoolCard(school: school)
            }
            if let disclaimer, !disclaimer.isEmpty {
                Text(disclaimer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GuideCompaniesSection: View {
    @EnvironmentObject private var router: AppRouter
    let companies: [KaiXGuideCompanyDTO]
    let disclaimer: String?

    var body: some View {
        if !companies.isEmpty {
            HStack {
                GuideSectionHeader(title: "外国人就职公司库", subtitle: "官方招聘页、签证支持与真实评价")
                Spacer()
                Button("查看全部") {
                    router.open(.guideCompanies)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.accent)
            }
            ForEach(companies.prefix(4)) { company in
                GuideCompanyCard(company: company)
            }
            Button {
                router.open(.guideInterviewReviews)
            } label: {
                Label("查看真实评论", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(KXColor.accentSoft, in: Capsule())
                    .foregroundStyle(KXColor.accent)
            }
            .buttonStyle(.plain)
            if let disclaimer, !disclaimer.isEmpty {
                Text(disclaimer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GuideFAQSection: View {
    let faq: [KaiXGuideFaqDTO]

    var body: some View {
        if !faq.isEmpty {
            GuideSectionHeader(title: "常见问题", subtitle: nil)
            VStack(spacing: 9) {
                ForEach(faq) { item in
                    DisclosureGroup {
                        Text(item.answer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .padding(.top, 6)
                    } label: {
                        Text(item.question)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(14)
                    .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
                }
            }
        }
    }
}

private struct GuideCategoryCard: View {
    @EnvironmentObject private var router: AppRouter
    let category: KaiXGuideCategoryDTO

    var body: some View {
        Button {
            category.key == "guide_services" ? router.open(.guideServices) : router.open(.guideCategory(categoryKey: category.key))
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                GuideIconBubble(icon: GuideCopy.symbol(for: category.icon), color: GuideCopy.color(category.color), size: 40)
                Text(category.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(category.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            .padding(13)
            .kxLivingSurface(radius: 22)
        }
        .buttonStyle(.plain)
    }
}

private struct GuideArticleCard: View {
    @EnvironmentObject private var router: AppRouter
    let article: KaiXGuideArticleDTO
    var compact = false

    var body: some View {
        Button {
            router.open(.guideArticle(slug: article.slug))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("指南")
                        .font(.caption2.weight(.bold))
                    .foregroundStyle(KXColor.livingAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                    .background(KXColor.livingAccentSoft, in: Capsule())
                    Text(article.authorName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text(article.title)
                    .font((compact ? Font.callout : Font.headline).weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(article.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                FlowLayout(spacing: 5) {
                    ForEach(article.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(KXColor.softBackground, in: Capsule())
                    }
                }
            }
            .padding(compact ? 14 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxLivingSurface(radius: 20)
        }
        .buttonStyle(.plain)
    }
}

private struct GuideProductCard: View {
    @EnvironmentObject private var router: AppRouter
    let product: KaiXGuideProductDTO

    var body: some View {
        Button {
            router.open(.guideProduct(slug: product.slug))
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(GuideCopy.productTypeLabel(product.productType))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(GuideCopy.productPrice(product))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(product.isService ? KXColor.rankTeal : (product.isComingSoon ? KXColor.heat : KXColor.accent))
                }
                Text(product.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !product.subtitle.isEmpty {
                    Text(product.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if !product.targetAudience.isEmpty {
                    Text("适合：\(product.targetAudience)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct GuideSchoolCard: View {
    @EnvironmentObject private var router: AppRouter
    let school: KaiXGuideSchoolDTO

    var body: some View {
        Button {
            router.open(.guideSchool(id: school.slug.isEmpty ? school.id : school.slug))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    GuideIconBubble(icon: "graduationcap.fill", color: KXColor.rankSky, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(school.schoolName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !school.schoolNameJp.isEmpty {
                            Text(school.schoolNameJp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(GuideCopy.schoolTypeLabel(school.schoolType))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KXColor.rankSky)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(KXColor.rankSky.opacity(0.10), in: Capsule())
                }
                Text(school.shortDescription.isEmpty ? school.description : school.shortDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 10) {
                    Text(GuideCopy.cityLabel(school.city))
                    Text(GuideCopy.levelLabel(school.requiredJapaneseLevel))
                    Text(GuideCopy.joinedOrPending(school.admissionMonths))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(school.fieldsOfStudy.prefix(3), id: \.self) { field in
                        GuideBadge(field)
                    }
                    GuideBadge(GuideCopy.triStateLabel(school.isAcceptingInternationalStudents, trueText: "留学生招生"), tint: KXColor.rankSky)
                }
            }
            .padding(14)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct GuideCompanyCard: View {
    @EnvironmentObject private var router: AppRouter
    let company: KaiXGuideCompanyDTO

    var body: some View {
        Button {
            router.open(.guideCompany(id: company.slug.isEmpty ? company.id : company.slug))
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    GuideIconBubble(icon: "building.2.fill", color: KXColor.rankTeal, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(company.companyName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        if !company.companyNameJp.isEmpty {
                            Text(company.companyNameJp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(company.industry.isEmpty ? "公司" : company.industry)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(KXColor.softBackground, in: Capsule())
                }
                HStack(spacing: 10) {
                    Text(GuideCopy.cityLabel(company.city))
                    if company.foundedYear > 0 { Text("成立 \(company.foundedYear)") }
                    Text(company.reviewCount > 0 ? "\(company.reviewCount) 条真实评价" : "暂无评价")
                        .foregroundStyle(company.reviewCount > 0 ? KXColor.accent : .secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let shortDescription = company.shortDescription, !shortDescription.isEmpty {
                    Text(shortDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                FlowLayout(spacing: 6) {
                    GuideBadge(GuideCopy.triStateLabel(company.acceptsForeignApplicants, trueText: "外国人申请"), tint: KXColor.rankTeal)
                    GuideBadge(GuideCopy.triStateLabel(company.supportsWorkVisa, trueText: "签证支持"), tint: KXColor.accent)
                    if let level = company.requiredJapaneseLevel, !level.isEmpty {
                        GuideBadge("日语 \(GuideCopy.levelLabel(level))", tint: KXColor.rankSky)
                    }
                }
            }
            .padding(14)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct GuideCompanyPositionCard: View {
    let position: KaiXGuideCompanyPositionDTO

    var body: some View {
        KXCard(padding: 14, radius: 20) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(position.positionTitle)
                            .font(.headline.weight(.bold))
                        if !position.positionTitleJp.isEmpty {
                            Text(position.positionTitleJp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if !position.employmentType.isEmpty {
                        GuideBadge(position.employmentType, tint: KXColor.rankTeal)
                    }
                }
                FlowLayout(spacing: 6) {
                    if !position.positionCategory.isEmpty { GuideBadge(position.positionCategory) }
                    if !position.city.isEmpty { GuideBadge(GuideCopy.cityLabel(position.city), tint: KXColor.rankSky) }
                    if !position.remoteType.isEmpty { GuideBadge(position.remoteType) }
                    let salary = GuideCopy.moneyRange(min: position.salaryMin, max: position.salaryMax, currency: position.currency)
                    if salary != "待补充" { GuideBadge(salary, tint: KXColor.rankGold) }
                    if !position.visaSupport.isEmpty { GuideBadge("签证 \(position.visaSupport)", tint: KXColor.accent) }
                }
                if !position.description.isEmpty {
                    Text(position.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !position.requirements.isEmpty {
                    Text("要求：\(position.requirements)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = GuideCopy.url(position.sourceUrl) {
                    Link("官方岗位页面", destination: url)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                }
            }
        }
    }
}

private struct GuideInterviewReviewCard: View {
    let review: KaiXGuideInterviewReviewDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FlowLayout(spacing: 6) {
                if let companyName = review.companyName, !companyName.isEmpty {
                    GuideBadge(companyName, tint: KXColor.accent)
                }
                if !review.position.isEmpty { GuideBadge(review.position) }
                if !review.difficulty.isEmpty { GuideBadge("难度：\(review.difficulty)") }
                if !review.result.isEmpty { GuideBadge("结果：\(review.result)") }
            }
            if !review.questions.isEmpty {
                Text(review.questions)
                    .font(.callout)
                    .lineLimit(3)
            }
            if !review.processDescription.isEmpty {
                Text(review.processDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text([review.interviewRounds > 0 ? "\(review.interviewRounds) 轮面试" : "", review.interviewLanguage, GuideCopy.cityLabel(review.city), review.interviewYear > 0 ? "\(review.interviewYear)" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
    }
}

private struct GuideWorkReviewCard: View {
    let review: KaiXGuideCompanyReviewDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FlowLayout(spacing: 6) {
                if !review.position.isEmpty { GuideBadge(review.position, tint: KXColor.accent) }
                if !review.employmentType.isEmpty { GuideBadge(review.employmentType) }
                if review.recommendationScore > 0 { GuideBadge("推荐 \(String(format: "%.1f", review.recommendationScore))/5") }
            }
            if !review.pros.isEmpty {
                Text(review.pros)
                    .font(.callout)
                    .lineLimit(3)
            }
            if !review.cons.isEmpty {
                Text("需要留意：\(review.cons)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
    }
}

private struct GuideBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.985, green: 0.975, blue: 0.955),
                KXColor.pageBackground,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct GuideSectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}

private struct GuideIconBubble: View {
    let icon: String
    let color: Color
    var size: CGFloat = 50

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.40, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
            .shadow(color: color.opacity(0.22), radius: 9, y: 4)
    }
}

private struct GuidePillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(isSelected ? Color.white : .primary.opacity(0.76))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(isSelected ? KXColor.accent : KXColor.cardBackground, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : KXColor.separator, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct GuideBadge: View {
    let text: String
    var tint: Color = .secondary

    init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10), in: Capsule())
    }
}

private struct GuideNotePanel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
    }
}

private struct GuideMetaRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.primary.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct GuideScoreRow: View {
    let title: String
    let value: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(KXColor.softBackground)
                    Capsule().fill(KXColor.accent)
                        .frame(width: max(0, min(1, value / 5)) * proxy.size.width)
                }
            }
            .frame(height: 8)
            Text(String(format: "%.1f", value))
                .font(.caption.weight(.bold))
                .frame(width: 32, alignment: .trailing)
        }
    }
}

private enum GuideCopy {
    static func symbol(for icon: String?) -> String {
        switch icon {
        case "graduation": return "graduationcap.fill"
        case "briefcase": return "briefcase.fill"
        case "plane": return "airplane.departure"
        case "language": return "character.book.closed.fill"
        case "home": return "house.fill"
        case "package": return "shippingbox.fill"
        default: return "book.closed.fill"
        }
    }

    static func resourceSymbol(_ icon: String) -> String {
        switch icon {
        case "school", "graduation", "graduationcap": return "graduationcap.fill"
        case "company", "building", "briefcase": return "building.2.fill"
        default: return symbol(for: icon)
        }
    }

    static func resourceColor(_ key: String) -> Color {
        switch key {
        case "japan_schools": return KXColor.rankSky
        case "foreigner_friendly_companies": return KXColor.rankTeal
        default: return KXColor.accent
        }
    }

    static func color(_ hex: String?) -> Color {
        guard let hex, !hex.isEmpty else { return KXColor.accent }
        return Color(hex: hex) ?? KXColor.accent
    }

    static func cityLabel(_ city: String) -> String {
        switch city.lowercased() {
        case "tokyo": return "东京"
        case "osaka": return "大阪"
        case "kyoto": return "京都"
        case "yokohama": return "横滨"
        case "kobe": return "神户"
        case "saitama": return "埼玉"
        case "chiba": return "千叶"
        case "": return "日本全国"
        default: return city
        }
    }

    static func schoolTypeLabel(_ type: String) -> String {
        switch type {
        case "university": return "大学"
        case "graduate_school": return "大学院"
        case "junior_college": return "短期大学"
        case "college_of_technology": return "高专"
        case "vocational_school": return "专门学校"
        case "language_school": return "语言学校"
        case "university_preparatory": return "大学预备课程"
        default: return type.isEmpty ? "学校" : type
        }
    }

    static func levelLabel(_ level: String) -> String {
        let normalized = level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "待补充" }
        switch normalized.lowercased() {
        case "unknown", "未知", "tbd", "n/a": return "待补充"
        case "none": return "无明确要求"
        case "n1", "n2", "n3", "n4", "n5": return normalized.uppercased()
        case "business": return "商务水平"
        case "native": return "接近母语"
        default: return normalized
        }
    }

    static func triStateLabel(_ value: Bool?, trueText: String) -> String {
        switch value {
        case .some(true): return trueText
        case .some(false): return "未确认"
        case .none: return "待核实"
        }
    }

    static func sourceStatusLabel(_ status: String) -> String {
        switch status {
        case "verified": return "已核验"
        case "official": return "官方来源"
        case "needs_review": return "待核验"
        case "unverified": return "未核验"
        default: return status.isEmpty ? "待核验" : status
        }
    }

    static func joinedOrPending(_ values: [String]) -> String {
        let clean = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return clean.isEmpty ? "待补充" : clean.joined(separator: "、")
    }

    static func moneyRange(min: Int, max: Int, currency: String) -> String {
        guard min > 0 || max > 0 else { return "待补充" }
        let symbol: String
        switch currency {
        case "JPY", "CNY": symbol = "¥"
        case "USD": symbol = "$"
        default: symbol = currency.isEmpty ? "" : "\(currency) "
        }
        if min > 0, max > 0, min != max {
            return "\(symbol)\(min)-\(symbol)\(max)"
        }
        return "\(symbol)\(max > 0 ? max : min)"
    }

    static func url(_ value: String?) -> URL? {
        guard var raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("www.") {
            raw = "https://\(raw)"
        }
        return URL(string: raw)
    }

    static func productTypeLabel(_ type: String) -> String {
        switch type {
        case "pdf_material": return "PDF 资料"
        case "template": return "模板资料"
        case "checklist": return "清单"
        case "course": return "课程"
        case "consultation": return "咨询服务"
        case "resume_review": return "履历修改"
        case "research_plan_review": return "研究计划书修改"
        case "language_school_support": return "语言学校辅导"
        case "graduate_school_support": return "大学院辅导"
        case "interview_coaching": return "面试辅导"
        default: return "资料服务"
        }
    }

    static func productPrice(_ product: KaiXGuideProductDTO) -> String {
        if product.isComingSoon || product.status == "coming_soon" { return "即将开放" }
        if product.isPriceHidden == true || product.isAppointmentOnly == true { return "预约咨询" }
        if product.isService, product.priceLabel.isEmpty {
            if product.servicePriceType == "quote_required" { return "按需求报价" }
            if product.servicePriceType == "starting_from", let starting = product.startingPrice, starting > 0 {
                return "\(KaiXPriceFormatter.format(Double(starting), currency: product.currency)) 起"
            }
            return "预约咨询"
        }
        if product.isFree { return "免费" }
        if !product.priceLabel.isEmpty { return product.priceLabel }
        return KaiXPriceFormatter.format(Double(product.price), currency: product.currency, billingPeriod: product.billingPeriod)
    }

    static func productCTA(_ product: KaiXGuideProductDTO, busy: Bool, loggedIn: Bool) -> String {
        if busy { return "处理中" }
        if let cta = product.ctaLabel, !cta.isEmpty { return cta }
        if product.isService || product.isAppointmentOnly == true || product.isPriceHidden == true { return "预约咨询" }
        // Free resources never tell an already-signed-in user to "log in":
        // they're authenticated by the time they reach Guide (login wall), so
        // show the action they can actually take.
        if product.isFree { return loggedIn ? "免费查看" : "登录后查看" }
        return "即将开放"
    }

    static func productActionEnabled(_ product: KaiXGuideProductDTO, busy: Bool) -> Bool {
        if busy { return false }
        if product.isService { return true }
        return product.isFree && !product.isComingSoon
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

private extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self = Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
