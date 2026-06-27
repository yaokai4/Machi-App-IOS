import SwiftUI
import UIKit

/// Bottom inset for every Guide scroll view so the floating bottom tab bar never
/// covers the last item. Uses the app-wide `chrome.bottomContentPadding` (≈98pt
/// while the tab bar shows; a small value once a detail page hides it) + extra —
/// the same source Home/Discover use, so Guide stops being occluded and stays
/// consistent across iPhone SE / Dynamic Island / Pro Max safe areas.
struct GuideBottomInset: ViewModifier {
    @EnvironmentObject private var chrome: AppChromeState
    var extra: CGFloat = KXSpacing.xl
    func body(content: Content) -> some View {
        content.padding(.bottom, chrome.bottomContentPadding + extra)
    }
}

extension View {
    func guideBottomInset(extra: CGFloat = KXSpacing.xl) -> some View {
        modifier(GuideBottomInset(extra: extra))
    }
}

func guideText(_ language: AppLanguage, _ zh: String, _ ja: String, _ en: String) -> String {
    KXListingCopy.pickText(language, zh, ja, en)
}

struct GuideHomeView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var regionStore = RegionStore.shared
    @StateObject private var viewModel = GuideViewModel()
    @State private var searchTask: Task<Void, Never>?

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
            await KXPerf.measure("guide.loadInitial") {
                await viewModel.load(country: country)
            }
        }
        .refreshable {
            await viewModel.load(country: country, force: true)
        }
        // Library search is debounced so it runs as the user types without a
        // request per keystroke. Clearing the field cancels any pending query.
        .onChange(of: viewModel.searchText) { _, newValue in
            searchTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                viewModel.clearSearch()
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard !Task.isCancelled else { return }
                await viewModel.search(country: country, keyword: trimmed)
            }
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
                    // 资料库导航中心:品牌头 + 搜索框。不再是「今日」行动面板。
                    GuideLibraryHero(
                        searchText: $viewModel.searchText,
                        placeholder: home.hero.searchPlaceholder,
                        quickTags: home.hero.quickTags
                    )

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
                        // 高价值资料库优先:学校库 / 公司库在六大指南之前。
                        GuideLibraryDualEntry()

                        GuideCategoryGrid(categories: GuideSupportCatalog.orderedCategories(from: home.categories))

                        // 推荐内容 / 最新指南 / 热门资料 —— 承接 web /guide 内容资产。
                        // 两个 section 在数据为空时自动隐藏,不会留空位。
                        GuideArticleSection(
                            title: guideText(language, "最新指南", "最新ガイド", "Latest guides"),
                            subtitle: guideText(language, "热门与最近更新的指南文章", "人気・最近更新のガイド記事", "Popular and recently updated guides"),
                            articles: Array(home.featuredArticles.prefix(4)),
                            compact: true
                        )

                        GuideProductsSection(
                            products: home.featuredProducts,
                            title: guideText(language, "热门资料与服务", "人気の資料・サービス", "Popular resources & services"),
                            subtitle: guideText(language, "资料包、模板、清单与人工辅导", "資料パック・テンプレート・サポート", "Packs, templates, and coaching")
                        )

                        // 个人行动类工具(Todo/日历/管理)已移出指南首页,只留一个去
                        // 「我的工作台」的轻入口,避免「查资料」和「办事」混在一起。
                        GuidePersonalWorkbenchCTA()
                    }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, 10)
                .guideBottomInset()
                .kxReadableWidth()
            }
        } else {
            LoadingView()
        }
    }
}

struct GuideCategoryView: View {
    @Environment(\.appLanguage) private var language
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
    private var selectedScope: KaiXGuideCategoryDTO? {
        guard !selectedSubCategory.isEmpty else { return category }
        return category?.subCategories?.first { $0.key == selectedSubCategory } ?? category
    }
    private var scopeCountLabels: [String] {
        var labels: [String] = []
        if let count = selectedScope?.articleCount {
            labels.append(guideText(language, "\(count) 篇指南", "\(count) 件のガイド", "\(count) guides"))
        }
        if let count = selectedScope?.productCount {
            labels.append(guideText(language, "\(count) 个资料/服务", "\(count) 件の資料/サービス", "\(count) resources/services"))
        }
        return labels
    }

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
                            GuideInlineStatus(message: guideText(language, "更新失败：\(errorMessage)", "更新に失敗しました：\(errorMessage)", "Update failed: \(errorMessage)"))
                        }
                        if !products.isEmpty {
                            GuideProductsSection(
                                products: products,
                                title: categoryKey == "jlpt" ? guideText(language, "JLPT 资料包", "JLPT 資料パック", "JLPT resource packs") : guideText(language, "相关资料与服务", "関連資料・サービス", "Related resources and services"),
                                subtitle: categoryKey == "jlpt"
                                    ? guideText(language, "N1-N5 过去问趋势分析与原创练习 · 学习计划", "N1-N5 の出題傾向分析・オリジナル練習・学習計画", "N1-N5 trend analysis, original drills, and study plans")
                                    : guideText(language, "与本频道相关的资料、模板与服务", "このカテゴリに関連する資料、テンプレート、サービス", "Resources, templates, and services for this channel")
                            )
                        }
                        if articles.isEmpty {
                            KXStatePanel(title: guideText(language, "这个分类的指南正在整理中", "このカテゴリのガイドを準備中です", "Guides for this category are being prepared"), subtitle: guideText(language, "Machi 编辑部会持续补充内容。", "Machi 編集部が順次追加します。", "Machi editors will keep adding content."), systemImage: "book.closed")
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
        .navigationTitle(category?.title ?? guideText(language, "日本指南", "日本ガイド", "Japan Guide"))
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
                    Text(category?.title ?? guideText(language, "日本指南", "日本ガイド", "Japan Guide"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(KXColor.livingInk)
                    Text(category?.subtitle ?? guideText(language, "系统化日本生活与成长指南", "日本生活と成長の体系的なガイド", "Structured guides for life and growth in Japan"))
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
            if !scopeCountLabels.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(scopeCountLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(KXColor.livingMuted)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(KXColor.livingSurface.opacity(0.86), in: Capsule())
                    }
                }
            }
            if let selectedScope, selectedScope.key != category?.key, !selectedScope.description.isEmpty {
                Text(selectedScope.description)
                    .font(.caption)
                    .foregroundStyle(KXColor.livingMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(KXColor.livingSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    GuidePillButton(title: guideText(language, "全部", "すべて", "All"), isSelected: selectedSubCategory.isEmpty) {
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
                subCategoryKey: selectedSubCategory.isEmpty ? nil : selectedSubCategory,
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
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: 8) {
            KXSpinner(size: 14, lineWidth: 2)
            Text(guideText(language, "正在更新内容", "内容を更新しています", "Updating content"))
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
    @Environment(\.appLanguage) private var language
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var response: KaiXGuideArticleDetailResponse?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isMarkingRead = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    let slug: String
    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }
    private var isSignedIn: Bool { (KaiXBackend.token?.isEmpty == false) }

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
                        articleActionBar(article)
                        articleBody(article)
                        GuideNotePanel(text: guideText(language, "本内容由 \(article.authorName) 整理，仅供参考。涉及签证、入管、考试等官方流程时，请同时以官方最新公告为准。", "本コンテンツは \(article.authorName) が整理した参考情報です。ビザ、入管、試験などの公式手続きは必ず最新の公式発表も確認してください。", "This content was curated by \(article.authorName) for reference only. For visas, immigration, exams, and other official processes, always check the latest official notices."))
                        if let related = response?.related, !related.isEmpty {
                            GuideArticleSection(title: guideText(language, "相关指南", "関連ガイド", "Related guides"), subtitle: nil, articles: related, compact: true)
                        }
                        // "Next step": route from this article into the matching
                        // action path so reading turns into doing.
                        GuideJourneyNextStepCard(categoryKey: article.categoryKey)
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            } else {
                EmptyStateView(title: guideText(language, "指南内容不存在", "ガイドが見つかりません", "Guide not found"), subtitle: guideText(language, "它可能已被移动或下线。", "移動または非公開になった可能性があります。", "It may have been moved or unpublished."), systemImage: "book.closed")
            }
        }
        .navigationTitle(guideText(language, "指南", "ガイド", "Guide"))
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

    private func articleHeader(_ article: KaiXGuideArticleDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(guideText(language, "指南", "ガイド", "Guide"))
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

    private func articleActionBar(_ article: KaiXGuideArticleDTO) -> some View {
        let progress = max(0, min(100, article.progressPercent ?? article.readingProgress?.progressPercent ?? 0))
        let saved = article.saved == true
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    Task { await toggleSave(article) }
                } label: {
                    Label(saved ? guideText(language, "已收藏", "保存済み", "Saved") : guideText(language, "收藏", "保存", "Save"),
                          systemImage: saved ? "bookmark.fill" : "bookmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.fullArea)
                .frame(minHeight: 46)
                .padding(.horizontal, 12)
                .background(KXColor.livingSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(KXColor.separator.opacity(0.55), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(isSaving)

                Button {
                    share(article)
                } label: {
                    Label(guideText(language, "分享", "共有", "Share"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.fullArea)
                .frame(minHeight: 46)
                .padding(.horizontal, 12)
                .background(KXColor.livingSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(KXColor.separator.opacity(0.55), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button {
                Task { await markRead(article) }
            } label: {
                HStack {
                    if isMarkingRead {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: progress >= 95 ? "checkmark.seal.fill" : "checkmark.circle")
                    }
                    Text(progress >= 95 ? guideText(language, "已读完", "読了", "Finished") : guideText(language, "标记读完", "読了にする", "Mark as read"))
                    Spacer()
                    Text("\(progress)%")
                        .font(.caption.weight(.black))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.fullArea)
            .disabled(isMarkingRead || progress >= 95)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(KXColor.softBackground)
                    Capsule()
                        .fill(KXColor.accent)
                        .frame(width: max(8, proxy.size.width * CGFloat(progress) / 100))
                }
            }
            .frame(height: 7)
        }
        .padding(14)
        .kxGlassSurface(radius: 20)
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
        await load(showSpinner: true)
    }

    private func load(showSpinner: Bool) async {
        guard country == "jp" else {
            isLoading = false
            response = nil
            return
        }
        if showSpinner { isLoading = true }
        errorMessage = nil
        defer { if showSpinner { isLoading = false } }
        do {
            response = try await KaiXAPIClient.shared.guideArticle(slug, country: country)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleSave(_ article: KaiXGuideArticleDTO) async {
        guard isSignedIn else {
            toastMessage = guideText(language, "登录后即可收藏指南。", "ログインするとガイドを保存できます。", "Sign in to save this guide.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await KaiXAPIClient.shared.setGuideSaved(itemType: "article", itemId: article.id, on: article.saved != true)
            toastMessage = article.saved == true
                ? guideText(language, "已取消收藏", "保存を解除しました", "Removed from saved")
                : guideText(language, "已收藏到资料库", "資料庫に保存しました", "Saved")
            await load(showSpinner: false)
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    private func markRead(_ article: KaiXGuideArticleDTO) async {
        guard isSignedIn else {
            toastMessage = guideText(language, "登录后即可保存阅读进度。", "ログインすると読書進捗を保存できます。", "Sign in to save reading progress.")
            return
        }
        isMarkingRead = true
        defer { isMarkingRead = false }
        do {
            _ = try await KaiXAPIClient.shared.updateGuideArticleProgress(article.slug, country: country, progressPercent: 100)
            toastMessage = guideText(language, "已标记读完", "読了にしました", "Marked as read")
            await load(showSpinner: false)
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    private func share(_ article: KaiXGuideArticleDTO) {
        UIPasteboard.general.string = "https://machicity.com/guide/articles/\(article.slug)"
        toastMessage = guideText(language, "链接已复制", "リンクをコピーしました", "Link copied")
    }
}

struct GuideServicesView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var products: [KaiXGuideProductDTO] = []
    @State private var productType = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }
    private var filters: [(String, String)] {
        [
            ("", guideText(language, "全部", "すべて", "All")),
            ("pdf_material", guideText(language, "PDF 资料", "PDF 資料", "PDF resources")),
            ("template", guideText(language, "模板", "テンプレート", "Templates")),
            ("checklist", guideText(language, "清单", "チェックリスト", "Checklists")),
            ("resume_review", guideText(language, "履历修改", "履歴書添削", "Resume review")),
            ("consultation", guideText(language, "咨询", "相談", "Consultation")),
        ]
    }

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
                            EmptyStateView(title: guideText(language, "暂无相关资料或服务", "関連資料・サービスはまだありません", "No related resources or services yet"), subtitle: guideText(language, "更多资料正在准备中。", "追加資料を準備中です。", "More resources are being prepared."), systemImage: "shippingbox")
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
        .navigationTitle(guideText(language, "商城", "ストア", "Store"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: productType) { await load() }
    }

    private var servicesHeader: some View {
        KXCard(padding: 16, radius: 22) {
            HStack(alignment: .top, spacing: 12) {
                GuideIconBubble(icon: "shippingbox.fill", color: KXColor.heat)
                VStack(alignment: .leading, spacing: 5) {
                    Text(guideText(language, "商城", "ストア", "Store"))
                        .font(.title2.weight(.bold))
                    Text(guideText(language, "资料包、模板、清单、课程与人工辅导服务", "資料パック、テンプレート、チェックリスト、講座、個別サポート", "Resource packs, templates, checklists, courses, and coaching services"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(guideText(language, "付费数字资料在 Apple IAP 接入前显示「即将开放」。服务类可先提交预约咨询。", "有料デジタル資料は Apple IAP 接続前は「まもなく公開」と表示されます。サービスは先に予約相談できます。", "Paid digital resources show as coming soon until Apple IAP is connected. Services can accept appointment inquiries first."))
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
    @Environment(\.appLanguage) private var language
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
    private var filters: [(String, String)] {
        [
            ("", guideText(language, "全部", "すべて", "All")),
            ("jlpt", guideText(language, "日语", "日本語", "Japanese")),
            ("study_japan", guideText(language, "升学", "進学", "Study")),
            ("career_japan", guideText(language, "就职", "就職", "Career")),
            ("life_japan", guideText(language, "生活", "生活", "Life")),
            ("study_abroad_japan", guideText(language, "留学", "留学", "Study abroad")),
            ("guide_services", guideText(language, "模板", "テンプレート", "Templates")),
        ]
    }

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
                            EmptyStateView(title: guideText(language, "暂无会员资料", "会員資料はまだありません", "No member resources yet"), subtitle: guideText(language, "更多资料正在整理中。", "追加資料を準備中です。", "More resources are being prepared."), systemImage: "crown")
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
        .navigationTitle(guideText(language, "会员专属资料", "会員専用資料", "Member resources"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(categoryKey):\(keyword)") { await load() }
    }

    private var header: some View {
        KXCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    GuideIconBubble(icon: "crown.fill", color: KXColor.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(guideText(language, "会员专属资料", "会員専用資料", "Member resources"))
                            .font(.title2.weight(.bold))
                        Text(guideText(language, "为 Machi 认证会员整理的日本升学、就职、日语和生活资料。", "Machi 認証会員向けに、日本進学・就職・日本語・生活資料を整理しています。", "Study, career, Japanese, and life resources for Machi verified members."))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(guideText(language, "服务类不进入会员免费权益；数字内容在 iOS 端遵守 Apple IAP 规则。", "サービス類は会員無料特典に含まれません。デジタル内容は iOS で Apple IAP ルールに従います。", "Services are not included in member freebies; digital content follows Apple IAP rules on iOS."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !membershipActive {
                    Text(guideText(language, "非会员可查看预览，完整内容需开通会员或在 Web 端完成相应购买后同步查看。", "非会員はプレビューを確認できます。全文は会員登録、または Web で購入後に同じアカウントで同期して閲覧できます。", "Non-members can view previews. Full content is available after membership or a synced web purchase."))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KXColor.accent)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(guideText(language, "搜索会员资料", "会員資料を検索", "Search member resources"), text: $keyword)
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
    @Environment(\.appLanguage) private var language
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var product: KaiXGuideProductDTO?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?
    @State private var showTopupSheet = false

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
                        GuideNotePanel(text: guideText(language, "数字资料商品在 Apple IAP 接入前显示「即将开放」。服务类只提交预约咨询，不在 iOS 内提供外部支付按钮。", "デジタル資料は Apple IAP 接続前は「まもなく公開」と表示されます。サービス類は予約相談のみで、iOS 内に外部決済ボタンは表示しません。", "Digital resources show as coming soon until Apple IAP is connected. Services only submit appointment inquiries; no external payment buttons are shown in iOS."))
                    }
                    .padding(KXSpacing.screen)
                    .guideBottomInset()
                }
            } else {
                EmptyStateView(title: guideText(language, "资料/服务不存在", "資料/サービスが見つかりません", "Resource/service not found"), subtitle: guideText(language, "它可能已被移动或下线。", "移動または非公開になった可能性があります。", "It may have been moved or unpublished."), systemImage: "shippingbox")
            }
        }
        .navigationTitle(guideText(language, "商城", "ストア", "Store"))
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
        .sheet(isPresented: $showTopupSheet, onDismiss: { Task { await load() } }) {
            NavigationStack { WalletView() }
        }
    }

    private func productHero(_ product: KaiXGuideProductDTO) -> some View {
        let price = GuideCopy.productPrice(product, language: language)
        return KXCard(padding: 18, radius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 13) {
                    GuideIconBubble(icon: product.isService ? "wrench.and.screwdriver.fill" : "doc.text.fill", color: product.isService ? KXColor.rankTeal : KXColor.heat)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(GuideCopy.productTypeLabel(product.productType, language: language))
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
                        Text(GuideCopy.productCTA(product, busy: isSubmitting, loggedIn: KaiXBackend.token != nil, language: language))
                            .font(.subheadline.weight(.bold))
                            .frame(height: 40)
                            .padding(.horizontal, 18)
                            .background(GuideCopy.productActionEnabled(product, busy: isSubmitting) ? KXColor.accent : Color.secondary.opacity(0.20), in: Capsule())
                            .foregroundStyle(GuideCopy.productActionEnabled(product, busy: isSubmitting) ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.fullArea)
        .contentShape(Rectangle())
                    .disabled(!GuideCopy.productActionEnabled(product, busy: isSubmitting))
                }
                if product.canBuyWithPoints == true && product.access?.canAccess != true {
                    Button {
                        Task { await productPointsAction(product) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.orange)
                            Text(pointsCTALabel(product))
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(KXColor.accentSoft, in: Capsule())
                        .foregroundStyle(KXColor.accent)
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .disabled(isSubmitting)
                    if let ctx = product.pointsContext, ctx.sufficient == false {
                        Text(guideText(language,
                            "当前余额 \(ctx.currentBalance ?? 0) 币，充值后可用 Machi 币购买。",
                            "残高 \(ctx.currentBalance ?? 0) コイン。チャージ後に Machi コインで購入できます。",
                            "Balance: \(ctx.currentBalance ?? 0) coins — top up to buy with Machi Coins."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func pointsCTALabel(_ product: KaiXGuideProductDTO) -> String {
        let pts = product.pointsContext?.requiredPoints ?? product.walletPricePoints ?? 0
        return guideText(language, "用 \(pts) 币购买", "\(pts) コインで購入", "Buy with \(pts) coins")
    }

    private func productPointsAction(_ product: KaiXGuideProductDTO) async {
        guard !isSubmitting else { return }
        if KaiXBackend.token == nil {
            toastMessage = guideText(language, "请登录后购买。", "ログインして購入してください。", "Please log in to purchase.")
            return
        }
        // Not enough points → open the top-up sheet instead of charging.
        if let ctx = product.pointsContext, ctx.sufficient == false {
            showTopupSheet = true
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let resp = try await KaiXAPIClient.shared.purchaseGuideProductWithWallet(product.slug)
            toastMessage = resp.message ?? guideText(language, "购买成功。", "購入が完了しました。", "Purchase complete.")
            await load()
        } catch {
            // Most likely insufficient balance (402) — send the user to top up.
            showTopupSheet = true
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
                GuideMetaRow(title: guideText(language, "适合人群", "対象者", "Best for"), value: product.targetAudience)
            }
            if !product.deliveryMethod.isEmpty {
                GuideMetaRow(title: guideText(language, "交付方式", "提供方法", "Delivery"), value: product.deliveryMethod)
            }
            GuideMetaRow(title: guideText(language, "内容类型", "コンテンツ種別", "Content type"), value: product.isService ? guideText(language, "人工服务", "人的サービス", "Human service") : guideText(language, "数字内容", "デジタル内容", "Digital content"))
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
                Label(product.access?.memberUnlocked == true ? guideText(language, "会员已解锁", "会員特典で解除済み", "Unlocked by membership") : guideText(language, "已购买", "購入済み", "Purchased"), systemImage: "checkmark.seal.fill")
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
                        Label(guideText(language, "下载资料", "資料をダウンロード", "Download resource"), systemImage: "arrow.down.circle.fill")
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
                Label(guideText(language, "预览内容", "プレビュー", "Preview"), systemImage: "lock.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if locked {
                    Text(guideText(language, "完整内容请在 Web 端购买或开通会员后，于 iOS 登录同一账号查看。", "全文は Web で購入または会員登録後、iOS で同じアカウントにログインして確認してください。", "Buy on the web or activate membership, then sign in with the same account on iOS to view the full content."))
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
                    message: guideText(language, "我想预约：\(product.title)", "\(product.title) を予約相談したいです", "I would like to book: \(product.title)")
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

struct GuideComingSoonView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject private var regionStore = RegionStore.shared
    var empty: KaiXGuideEmptyStateDTO?

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            GuideIconBubble(icon: "airplane.departure", color: KXColor.rankSky, size: 68)
            Text(empty?.title ?? guideText(language, "Machi 指南目前只开放日本地区", "Machi Guide は現在日本エリアのみ公開中です", "Machi Guide is currently available for Japan only"))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(empty?.body ?? guideText(language, "如果你正在准备日本留学、升学、就职，或在备考日语（JLPT）、了解在日生活，切换到日本地区即可查看完整的指南、学校库、公司库与资料服务。其他国家和地区将陆续开放。", "日本留学、進学、就職、JLPT 対策、日本生活の準備中なら、日本エリアに切り替えるとガイド、学校データベース、企業データベース、資料サービスを確認できます。他の国と地域も順次公開予定です。", "Switch to Japan to view guides, school and company libraries, and resource services for study abroad, school admissions, careers, JLPT prep, and life in Japan. Other countries and regions will open gradually."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 26)
            Button {
                _ = regionStore.setCurrent(country: "jp", province: "tokyo", city: "tokyo")
            } label: {
                Text(empty?.action ?? guideText(language, "切换到日本地区", "日本エリアに切り替え", "Switch to Japan"))
                    .font(.subheadline.weight(.bold))
                    .frame(height: 44)
                    .padding(.horizontal, 22)
                    .background(KXColor.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.fullArea)
        .contentShape(Rectangle())
            Spacer(minLength: 80)
        }
        .padding()
    }
}

struct GuideSchoolFilterSheet: View {
    @Environment(\.appLanguage) private var language
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
                    group(guideText(language, "学校类型", "学校種別", "School type"), options: [("", guideText(language, "全部", "すべて", "All")), ("university", guideText(language, "大学", "大学", "University")), ("graduate_school", guideText(language, "大学院", "大学院", "Graduate school")), ("junior_college", guideText(language, "短大", "短大", "Junior college")), ("college_of_technology", guideText(language, "高专", "高専", "College of technology")), ("vocational_school", guideText(language, "专门学校", "専門学校", "Vocational school")), ("language_school", guideText(language, "语言学校", "語学学校", "Language school"))], selection: $schoolType, toggle: false)
                    group(guideText(language, "圈域", "エリア", "Area"), options: [("capital_area", guideText(language, "首都圈", "首都圏", "Capital area")), ("kansai_area", guideText(language, "关西圈", "関西圏", "Kansai area"))], selection: $regionGroup, toggle: true)
                    group(guideText(language, "都道府县", "都道府県", "Prefecture"), options: [("", guideText(language, "全部", "すべて", "All")), ("tokyo", "Tokyo"), ("kanagawa", "Kanagawa"), ("chiba", "Chiba"), ("saitama", "Saitama"), ("kyoto", "Kyoto"), ("osaka", "Osaka"), ("hyogo", "Hyogo")], selection: $prefecture, toggle: false)
                    group(guideText(language, "专业领域", "専攻分野", "Field"), options: [("", guideText(language, "全部", "すべて", "All")), ("engineering", guideText(language, "工学", "工学", "Engineering")), ("business", guideText(language, "经营", "経営", "Business")), ("it", "IT"), ("language", guideText(language, "语言", "語学", "Language")), ("design", guideText(language, "设计", "デザイン", "Design"))], selection: $field, toggle: false)
                    group(guideText(language, "支持条件", "サポート条件", "Support"), options: [("international", guideText(language, "留学生可申请", "留学生出願可", "International students")), ("english", guideText(language, "英文项目", "英語プログラム", "English programs")), ("japanese", guideText(language, "日语项目", "日本語プログラム", "Japanese programs")), ("scholarship", guideText(language, "奖学金", "奨学金", "Scholarship")), ("dormitory", guideText(language, "宿舍", "寮", "Dormitory")), ("career", guideText(language, "就职支持", "就職支援", "Career support")), ("language_support", guideText(language, "语言支持", "語学サポート", "Language support"))], selection: $supportFilter, toggle: true)
                    group(guideText(language, "排序", "並び替え", "Sort"), options: [("recommended", guideText(language, "推荐", "おすすめ", "Recommended")), ("data_quality", guideText(language, "完整度", "充実度", "Completeness")), ("recently_updated", guideText(language, "最近更新", "最近更新", "Recently updated")), ("popular", guideText(language, "人气", "人気", "Popular")), ("name_jp_asc", guideText(language, "日文名", "日本語名", "Japanese name"))], selection: $sort, toggle: false)
                }
                .padding(KXSpacing.screen)
            }
            .navigationTitle(guideText(language, "筛选学校", "学校を絞り込み", "Filter schools"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(guideText(language, "重置", "リセット", "Reset")) {
                        schoolType = ""; regionGroup = ""; prefecture = ""; field = ""; supportFilter = ""; sort = "recommended"
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(guideText(language, "应用", "適用", "Apply")) { dismiss() }.fontWeight(.bold)
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

/// Guide-home hero. 资料库导航中心:品牌头 + 标题「日本指南」+ 搜索框 + 快捷标签。
/// No "今日" / Todo here — personal action tools live in 我的工作台.
/// Search is driven by a debounced `.onChange` on the bound `searchText` in the
/// host (`GuideHomeView`), so this view only needs to mutate the binding.
private struct GuideLibraryHero: View {
    @Environment(\.appLanguage) private var language
    @Binding var searchText: String
    let placeholder: String
    let quickTags: [String]

    private var resolvedPlaceholder: String {
        placeholder.isEmpty
            ? guideText(language, "搜索学校、公司、签证、JLPT、租房、研究计划书", "学校・企業・ビザ・JLPT・賃貸・研究計画書を検索", "Search schools, companies, visas, JLPT, housing, research plans")
            : placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "book.pages")
                Text(guideText(language, "Machi Guide · 日本指南", "Machi Guide · 日本ガイド", "Machi Guide · Japan"))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(KXColor.livingAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(KXColor.livingAccentSoft, in: Capsule())

            Text(guideText(language, "日本指南", "日本ガイド", "Japan Guide"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(KXColor.livingInk)
            Text(guideText(
                language,
                "查学校、公司、签证、申请、日语和在日生活方法。",
                "学校・企業・ビザ・出願・日本語・生活情報をまとめて確認。",
                "Find schools, companies, visas, applications, Japanese study, and life guides."
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(KXColor.livingMuted)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(KXColor.livingAccent)
                TextField(resolvedPlaceholder, text: $searchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .accessibilityIdentifier("guide.search.field")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("guide.search.clear")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(KXColor.livingInk.opacity(0.08), lineWidth: 0.8)
            }

            if !quickTags.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(quickTags, id: \.self) { tag in
                        Button {
                            searchText = tag
                        } label: {
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary.opacity(0.78))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(KXColor.livingSurface.opacity(0.82), in: Capsule())
                        }
                        .buttonStyle(.fullArea)
                        .contentShape(Rectangle())
                    }
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
    @Environment(\.appLanguage) private var language
    let isSearching: Bool
    let articles: [KaiXGuideArticleDTO]
    let schools: [KaiXGuideSchoolDTO]
    let companies: [KaiXGuideCompanyDTO]

    private var total: Int { articles.count + schools.count + companies.count }

    var body: some View {
        GuideSectionHeader(
            title: guideText(language, "搜索结果", "検索結果", "Search results"),
            subtitle: isSearching ? guideText(language, "正在查找学校、公司和指南", "学校・会社・ガイドを検索中", "Searching schools, companies, and guides") : guideText(language, "共 \(total) 条 · 学校 / 公司 / 指南都已包含", "合計 \(total) 件 · 学校 / 会社 / ガイドを含む", "\(total) total · schools / companies / guides included")
        )
        if isSearching {
            LoadingView()
        } else if total == 0 {
            EmptyStateView(title: guideText(language, "没有找到相关内容", "関連内容が見つかりません", "No matching content"), subtitle: guideText(language, "换个关键词试试，可以搜学校、公司名和任意指南内容。", "別のキーワードを試してください。学校名、会社名、ガイド内容で検索できます。", "Try another keyword. You can search school names, company names, or guide content."), systemImage: "magnifyingglass")
        } else {
            if !schools.isEmpty {
                groupLabel(icon: "graduationcap.fill", title: guideText(language, "学校", "学校", "Schools"), count: schools.count)
                ForEach(schools) { GuideSchoolCard(school: $0) }
            }
            if !companies.isEmpty {
                groupLabel(icon: "building.2.fill", title: guideText(language, "就职公司", "就職企業", "Companies"), count: companies.count)
                ForEach(companies) { GuideCompanyCard(company: $0) }
            }
            if !articles.isEmpty {
                groupLabel(icon: "doc.text.fill", title: guideText(language, "指南文章", "ガイド記事", "Guide articles"), count: articles.count)
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
    @Environment(\.appLanguage) private var language
    let categories: [KaiXGuideCategoryDTO]

    var body: some View {
        if !categories.isEmpty {
            Divider()
                .padding(.top, 4)
            GuideSectionHeader(
                title: guideText(language, "六大指南", "6つのガイド", "Guide categories"),
                subtitle: guideText(
                    language,
                    "按目标进入系统化指南，先看路径，再查资料和服务。",
                    "目的別にガイドを確認し、流れ・資料・サービスへ進みます。",
                    "Browse structured guides by goal, then open resources and services."
                )
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(categories) { category in
                    GuideCategoryCard(category: category)
                }
            }
        }
    }
}

/// 核心资料库:学校库(蓝) + 公司库(青绿)。两张高对比大卡,放在六大指南之前,
/// 是 Guide 首屏最醒目的高价值入口(比普通指南卡更突出)。
private struct GuideLibraryDualEntry: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionHeader(
                title: guideText(language, "核心资料库", "コア資料庫", "Core libraries"),
                subtitle: guideText(
                    language,
                    "查学校和适合外国人就职的公司，先从这两个库开始。",
                    "学校と外国人向け企業。まずこの2つから。",
                    "Start with schools and foreigner-friendly employers."
                )
            )
            HStack(spacing: 12) {
                card(
                    title: guideText(language, "日本学校库", "学校データベース", "School library"),
                    subtitle: guideText(language, "大学、大学院、专门学校、语言学校", "大学・大学院・専門・語学", "Universities, grad, vocational, language"),
                    icon: "graduationcap.fill",
                    colors: [Color.blue, Color.blue.opacity(0.78)],
                    identifier: "guide.library.schools"
                ) { router.open(.guideSchools) }

                card(
                    title: guideText(language, "就职公司库", "就職企業データベース", "Company library"),
                    subtitle: guideText(language, "外国人友好企业、签证支持与真实评价", "外国人歓迎・ビザ支援・口コミ", "Foreigner-friendly, visa support, reviews"),
                    icon: "building.2.fill",
                    colors: [Color.teal, Color.teal.opacity(0.78)],
                    identifier: "guide.library.companies"
                ) { router.open(.guideCompanies) }
            }
        }
    }

    private func card(title: String, subtitle: String, icon: String, colors: [Color], identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(guideText(language, "进入", "開く", "Open"))
                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
            .padding(16)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .shadow(color: (colors.first ?? .clear).opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
        .accessibilityIdentifier(identifier)
    }
}

/// The ONLY personal-action entry allowed on the Guide home: a single light CTA
/// to 我的工作台. Guide stays a reference library; Todo / 日历 / 管理 live in 我的.
private struct GuidePersonalWorkbenchCTA: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Button {
            router.open(.personalWorkbench)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .frame(width: 44, height: 44)
                    .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(guideText(language, "需要管理 Todo、日历和申请？", "Todo・カレンダー・申請を管理？", "Manage todos, calendar & applications?"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(guideText(language, "个人计划在「我的工作台」中管理", "個人の予定は「マイワークベンチ」で管理", "Your personal plans live in My Workbench"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Text(guideText(language, "去工作台", "開く", "Open"))
                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KXColor.separator.opacity(0.7), lineWidth: 0.8))
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
        .accessibilityIdentifier("guide.workbench.cta")
    }
}

private enum GuideSupportCatalog {
    private static let keys = [
        "study_japan",
        "career_japan",
        "study_abroad_japan",
        "jlpt",
        "life_japan",
        "guide_services"
    ]

    static func orderedCategories(from categories: [KaiXGuideCategoryDTO]) -> [KaiXGuideCategoryDTO] {
        let topLevel = categories.filter { $0.parentKey.isEmpty }
        return keys.compactMap { key in topLevel.first { $0.key == key } }
    }
}

private struct GuideGoalsSection: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let goals: String
    let entries: [KaiXGuideGoalEntryDTO]

    var body: some View {
        if !entries.isEmpty {
            GuideSectionHeader(title: goals, subtitle: guideText(language, "按你的目标快速进入", "目的別にすばやく移動", "Jump in by goal"))
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
                        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct GuideArticleSection: View {
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

struct GuideProductsSection: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let products: [KaiXGuideProductDTO]
    var title: String?
    var subtitle: String?

    var body: some View {
        if !products.isEmpty {
            HStack {
                GuideSectionHeader(title: title ?? guideText(language, "商城", "ストア", "Store"), subtitle: subtitle ?? guideText(language, "资料包、模板、清单与人工辅导", "資料パック、テンプレート、チェックリスト、個別サポート", "Resource packs, templates, checklists, and coaching"))
                Spacer()
                Button(guideText(language, "查看全部", "すべて見る", "View all")) {
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
/// membership lives behind Member area, while templates and human help live behind
/// 资料与服务. Side-by-side tiles so the split is legible at a glance.
private struct GuideDualEntrySection: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideSectionHeader(title: guideText(language, "会员与商城", "会員・ストア", "Membership and Store"), subtitle: guideText(language, "会员专属资料、原创资料包、模板与人工服务统一入口", "会員資料、オリジナル資料パック、テンプレート、人的サービスの入口", "One place for member resources, original packs, templates, and services"))
            HStack(spacing: 10) {
                entryTile(
                    icon: "crown.fill",
                    tint: KXColor.accent,
                    title: guideText(language, "会员专区", "会員エリア", "Member area"),
                    subtitle: guideText(language, "清单模板资料\n会员权益内容", "チェックリスト・テンプレート\n会員特典コンテンツ", "Checklists and templates\nMember content")
                ) {
                    router.open(.guideMemberResources)
                }
                entryTile(
                    icon: "bag.fill",
                    tint: .orange,
                    title: guideText(language, "商城", "ストア", "Store"),
                    subtitle: guideText(language, "资料包与人工服务\n按需购买预约", "資料パック・人的サービス\n必要に応じて購入/予約", "Resource packs and services\nBuy or book as needed")
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
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }
}

private struct GuideSchoolsSection: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let schools: [KaiXGuideSchoolDTO]
    let disclaimer: String?

    var body: some View {
        if !schools.isEmpty {
            HStack {
                GuideSectionHeader(title: guideText(language, "日本学校库", "日本の学校データベース", "Japan School Library"), subtitle: guideText(language, "大学、大学院、专门学校、语言学校", "大学、大学院、専門学校、語学学校", "Universities, graduate schools, vocational schools, language schools"))
                Spacer()
                Button(guideText(language, "查看全部", "すべて見る", "View all")) {
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
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let companies: [KaiXGuideCompanyDTO]
    let disclaimer: String?

    var body: some View {
        if !companies.isEmpty {
            HStack {
                GuideSectionHeader(title: guideText(language, "外国人就职公司库", "外国人向け就職企業データベース", "Foreigner-Friendly Company Library"), subtitle: guideText(language, "官方招聘页、签证支持与真实评价", "公式採用ページ、ビザ支援、実体験レビュー", "Official career pages, visa support, and real reviews"))
                Spacer()
                Button(guideText(language, "查看全部", "すべて見る", "View all")) {
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
                Label(guideText(language, "查看真实评论", "リアルレビューを見る", "View real reviews"), systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(KXColor.accentSoft, in: Capsule())
                    .foregroundStyle(KXColor.accent)
            }
            .buttonStyle(.fullArea)
        .contentShape(Rectangle())
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
    @Environment(\.appLanguage) private var language
    let faq: [KaiXGuideFaqDTO]

    var body: some View {
        if !faq.isEmpty {
            GuideSectionHeader(title: guideText(language, "常见问题", "よくある質問", "FAQ"), subtitle: nil)
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
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let category: KaiXGuideCategoryDTO
    private var countLabels: [String] {
        var labels: [String] = []
        if let count = category.articleCount {
            labels.append(guideText(language, "\(count) 篇", "\(count) 件", "\(count) articles"))
        }
        if let count = category.productCount {
            labels.append(guideText(language, "\(count) 个资料", "\(count) 件の資料", "\(count) resources"))
        }
        return labels
    }

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
                if !countLabels.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(countLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2.weight(.black))
                                .foregroundStyle(KXColor.livingMuted)
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(KXColor.softBackground.opacity(0.85), in: Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            .padding(13)
            .kxLivingSurface(radius: 22)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }
}

private struct GuideArticleCard: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let article: KaiXGuideArticleDTO
    var compact = false

    var body: some View {
        Button {
            router.open(.guideArticle(slug: article.slug))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(guideText(language, "指南", "ガイド", "Guide"))
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
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }
}

private struct GuideProductCard: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let product: KaiXGuideProductDTO

    var body: some View {
        Button {
            router.open(.guideProduct(slug: product.slug))
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(GuideCopy.productTypeLabel(product.productType, language: language))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(GuideCopy.productPrice(product, language: language))
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
                    Text(guideText(language, "适合：\(product.targetAudience)", "対象：\(product.targetAudience)", "Best for: \(product.targetAudience)"))
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
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }
}

struct GuideSchoolCard: View {
    @Environment(\.appLanguage) private var language
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
                    Text(GuideCopy.schoolTypeLabel(school.schoolType, language: language))
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
                    Text(GuideCopy.cityLabel(school.city, language: language))
                    Text(GuideCopy.levelLabel(school.requiredJapaneseLevel, language: language))
                    Text(GuideCopy.joinedOrPending(school.admissionMonths, language: language))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(school.fieldsOfStudy.prefix(3), id: \.self) { field in
                        GuideBadge(field)
                    }
                    GuideBadge(GuideCopy.triStateLabel(school.isAcceptingInternationalStudents, trueText: guideText(language, "留学生招生", "留学生募集", "International admissions"), language: language), tint: KXColor.rankSky)
                }
            }
            .padding(14)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }
}

struct GuideCompanyCard: View {
    @Environment(\.appLanguage) private var language
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
                    Text(company.industry.isEmpty ? guideText(language, "公司", "会社", "Company") : company.industry)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(KXColor.softBackground, in: Capsule())
                }
                HStack(spacing: 10) {
                    Text(GuideCopy.cityLabel(company.city, language: language))
                    if company.foundedYear > 0 { Text(guideText(language, "成立 \(company.foundedYear)", "\(company.foundedYear)年設立", "Founded \(company.foundedYear)")) }
                    Text(company.reviewCount > 0 ? guideText(language, "\(company.reviewCount) 条真实评价", "\(company.reviewCount) 件の実体験レビュー", "\(company.reviewCount) real reviews") : guideText(language, "暂无评价", "レビューはまだありません", "No reviews yet"))
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
                    GuideBadge(GuideCopy.triStateLabel(company.acceptsForeignApplicants, trueText: guideText(language, "外国人申请", "外国人応募", "Foreign applicants"), language: language), tint: KXColor.rankTeal)
                    GuideBadge(GuideCopy.triStateLabel(company.supportsWorkVisa, trueText: guideText(language, "签证支持", "ビザ支援", "Visa support"), language: language), tint: KXColor.accent)
                    if let level = company.requiredJapaneseLevel, !level.isEmpty {
                        GuideBadge(guideText(language, "日语 \(GuideCopy.levelLabel(level, language: language))", "日本語 \(GuideCopy.levelLabel(level, language: language))", "Japanese \(GuideCopy.levelLabel(level, language: language))"), tint: KXColor.rankSky)
                    }
                }
            }
            .padding(14)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }
}

struct GuideCompanyPositionCard: View {
    @Environment(\.appLanguage) private var language
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
                    if !position.city.isEmpty { GuideBadge(GuideCopy.cityLabel(position.city, language: language), tint: KXColor.rankSky) }
                    if !position.remoteType.isEmpty { GuideBadge(position.remoteType) }
                    let salary = GuideCopy.moneyRange(min: position.salaryMin, max: position.salaryMax, currency: position.currency, language: language)
                    if position.salaryMin > 0 || position.salaryMax > 0 { GuideBadge(salary, tint: KXColor.rankGold) }
                    if !position.visaSupport.isEmpty { GuideBadge(guideText(language, "签证 \(position.visaSupport)", "ビザ \(position.visaSupport)", "Visa \(position.visaSupport)"), tint: KXColor.accent) }
                }
                if !position.description.isEmpty {
                    Text(position.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !position.requirements.isEmpty {
                    Text(guideText(language, "要求：\(position.requirements)", "要件：\(position.requirements)", "Requirements: \(position.requirements)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = GuideCopy.url(position.sourceUrl) {
                    Link(guideText(language, "官方岗位页面", "公式求人ページ", "Official job page"), destination: url)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                }
            }
        }
    }
}

struct GuideInterviewReviewCard: View {
    @Environment(\.appLanguage) private var language
    let review: KaiXGuideInterviewReviewDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FlowLayout(spacing: 6) {
                if let companyName = review.companyName, !companyName.isEmpty {
                    GuideBadge(companyName, tint: KXColor.accent)
                }
                if !review.position.isEmpty { GuideBadge(review.position) }
                if !review.difficulty.isEmpty { GuideBadge(guideText(language, "难度：\(review.difficulty)", "難易度：\(review.difficulty)", "Difficulty: \(review.difficulty)")) }
                if !review.result.isEmpty { GuideBadge(guideText(language, "结果：\(review.result)", "結果：\(review.result)", "Result: \(review.result)")) }
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
            Text([review.interviewRounds > 0 ? guideText(language, "\(review.interviewRounds) 轮面试", "\(review.interviewRounds) 回面接", "\(review.interviewRounds) rounds") : "", review.interviewLanguage, GuideCopy.cityLabel(review.city, language: language), review.interviewYear > 0 ? "\(review.interviewYear)" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
    }
}

struct GuideWorkReviewCard: View {
    @Environment(\.appLanguage) private var language
    let review: KaiXGuideCompanyReviewDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FlowLayout(spacing: 6) {
                if !review.position.isEmpty { GuideBadge(review.position, tint: KXColor.accent) }
                if !review.employmentType.isEmpty { GuideBadge(review.employmentType) }
                if review.recommendationScore > 0 { GuideBadge(guideText(language, "推荐 \(String(format: "%.1f", review.recommendationScore))/5", "おすすめ \(String(format: "%.1f", review.recommendationScore))/5", "Recommendation \(String(format: "%.1f", review.recommendationScore))/5")) }
            }
            if !review.pros.isEmpty {
                Text(review.pros)
                    .font(.callout)
                    .lineLimit(3)
            }
            if !review.cons.isEmpty {
                Text(guideText(language, "需要留意：\(review.cons)", "気になる点：\(review.cons)", "Watch-outs: \(review.cons)"))
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

struct GuideBackground: View {
    var body: some View {
        // Both stops are dark-adaptive: a warm cream→page gradient in light
        // mode, a dark gradient in dark mode. (The top stop used to be a fixed
        // cream literal, leaving a bright band across the top in dark mode.)
        LinearGradient(
            colors: [
                KXColor.livingBackground,
                KXColor.pageBackground,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct GuideSectionHeader: View {
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

struct GuideIconBubble: View {
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

struct GuidePillButton: View {
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
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }
}

struct GuideBadge: View {
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

struct GuideNotePanel: View {
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

struct GuideMetaRow: View {
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

struct GuideScoreRow: View {
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

enum GuideCopy {
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

    static func cityLabel(_ city: String, language: AppLanguage = .zh) -> String {
        switch city.lowercased() {
        case "tokyo": return guideText(language, "东京", "東京", "Tokyo")
        case "osaka": return guideText(language, "大阪", "大阪", "Osaka")
        case "kyoto": return guideText(language, "京都", "京都", "Kyoto")
        case "yokohama": return guideText(language, "横滨", "横浜", "Yokohama")
        case "kobe": return guideText(language, "神户", "神戸", "Kobe")
        case "saitama": return guideText(language, "埼玉", "埼玉", "Saitama")
        case "chiba": return guideText(language, "千叶", "千葉", "Chiba")
        case "": return guideText(language, "日本全国", "日本全国", "All Japan")
        default: return city
        }
    }

    static func schoolTypeLabel(_ type: String, language: AppLanguage = .zh) -> String {
        switch type {
        case "university": return guideText(language, "大学", "大学", "University")
        case "graduate_school": return guideText(language, "大学院", "大学院", "Graduate school")
        case "junior_college": return guideText(language, "短期大学", "短期大学", "Junior college")
        case "college_of_technology": return guideText(language, "高专", "高専", "College of technology")
        case "vocational_school": return guideText(language, "专门学校", "専門学校", "Vocational school")
        case "language_school": return guideText(language, "语言学校", "語学学校", "Language school")
        case "university_preparatory": return guideText(language, "大学预备课程", "大学予備課程", "University preparatory")
        default: return type.isEmpty ? guideText(language, "学校", "学校", "School") : type
        }
    }

    static func levelLabel(_ level: String, language: AppLanguage = .zh) -> String {
        let normalized = level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return guideText(language, "待补充", "未入力", "Pending") }
        switch normalized.lowercased() {
        case "unknown", "未知", "tbd", "n/a": return guideText(language, "待补充", "未入力", "Pending")
        case "none": return guideText(language, "无明确要求", "明確な要件なし", "No clear requirement")
        case "n1", "n2", "n3", "n4", "n5": return normalized.uppercased()
        case "business": return guideText(language, "商务水平", "ビジネスレベル", "Business level")
        case "native": return guideText(language, "接近母语", "ネイティブ相当", "Near native")
        default: return normalized
        }
    }

    static func triStateLabel(_ value: Bool?, trueText: String, language: AppLanguage = .zh) -> String {
        switch value {
        case .some(true): return trueText
        case .some(false): return guideText(language, "未确认", "未確認", "Unconfirmed")
        case .none: return guideText(language, "待核实", "確認待ち", "Pending")
        }
    }

    static func sourceStatusLabel(_ status: String, language: AppLanguage = .zh) -> String {
        switch status {
        case "verified": return guideText(language, "已核验", "確認済み", "Verified")
        case "official": return guideText(language, "官方来源", "公式ソース", "Official source")
        case "needs_review": return guideText(language, "待核验", "確認待ち", "Needs review")
        case "unverified": return guideText(language, "未核验", "未確認", "Unverified")
        default: return status.isEmpty ? guideText(language, "待核验", "確認待ち", "Needs review") : status
        }
    }

    static func joinedOrPending(_ values: [String], language: AppLanguage = .zh) -> String {
        let clean = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return clean.isEmpty ? guideText(language, "待补充", "未入力", "Pending") : clean.joined(separator: language == .en ? ", " : "、")
    }

    static func moneyRange(min: Int, max: Int, currency: String, language: AppLanguage = .zh) -> String {
        guard min > 0 || max > 0 else { return guideText(language, "待补充", "未入力", "Pending") }
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

    static func productTypeLabel(_ type: String, language: AppLanguage = .zh) -> String {
        switch type {
        case "pdf_material": return guideText(language, "PDF 资料", "PDF 資料", "PDF resources")
        case "template": return guideText(language, "模板资料", "テンプレート資料", "Templates")
        case "checklist": return guideText(language, "清单", "チェックリスト", "Checklist")
        case "course": return guideText(language, "课程", "講座", "Course")
        case "consultation": return guideText(language, "咨询服务", "相談サービス", "Consultation")
        case "resume_review": return guideText(language, "履历修改", "履歴書添削", "Resume review")
        case "research_plan_review": return guideText(language, "研究计划书修改", "研究計画書添削", "Research plan review")
        case "language_school_support": return guideText(language, "语言学校辅导", "語学学校サポート", "Language school support")
        case "graduate_school_support": return guideText(language, "大学院辅导", "大学院サポート", "Graduate school support")
        case "interview_coaching": return guideText(language, "面试辅导", "面接対策", "Interview coaching")
        default: return guideText(language, "资料服务", "資料サービス", "Resource service")
        }
    }

    static func productPrice(_ product: KaiXGuideProductDTO, language: AppLanguage = .zh) -> String {
        if product.isComingSoon || product.status == "coming_soon" { return guideText(language, "即将开放", "まもなく公開", "Coming soon") }
        if product.isPriceHidden == true || product.isAppointmentOnly == true { return guideText(language, "预约咨询", "予約相談", "Consult") }
        if product.isService, product.priceLabel.isEmpty {
            if product.servicePriceType == "quote_required" { return guideText(language, "按需求报价", "要見積もり", "Quote required") }
            if product.servicePriceType == "starting_from", let starting = product.startingPrice, starting > 0 {
                let price = KaiXPriceFormatter.format(Double(starting), currency: product.currency)
                return guideText(language, "\(price) 起", "\(price) から", "From \(price)")
            }
            return guideText(language, "预约咨询", "予約相談", "Consult")
        }
        if product.isFree { return guideText(language, "免费", "無料", "Free") }
        if !product.priceLabel.isEmpty { return product.priceLabel }
        return KaiXPriceFormatter.format(Double(product.price), currency: product.currency, billingPeriod: product.billingPeriod)
    }

    static func productCTA(_ product: KaiXGuideProductDTO, busy: Bool, loggedIn: Bool, language: AppLanguage = .zh) -> String {
        if busy { return guideText(language, "处理中", "処理中", "Processing") }
        if let cta = product.ctaLabel, !cta.isEmpty { return cta }
        if product.isService || product.isAppointmentOnly == true || product.isPriceHidden == true { return guideText(language, "预约咨询", "予約相談", "Consult") }
        // Free resources never tell an already-signed-in user to "log in":
        // they're authenticated by the time they reach Guide (login wall), so
        // show the action they can actually take.
        if product.isFree { return loggedIn ? guideText(language, "免费查看", "無料で見る", "View free") : guideText(language, "登录后查看", "ログインして見る", "Sign in to view") }
        return guideText(language, "即将开放", "まもなく公開", "Coming soon")
    }

    static func productActionEnabled(_ product: KaiXGuideProductDTO, busy: Bool) -> Bool {
        if busy { return false }
        if product.isService { return true }
        return product.isFree && !product.isComingSoon
    }
}

extension String {
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
