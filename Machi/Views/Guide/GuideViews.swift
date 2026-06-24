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

private func guideText(_ language: AppLanguage, _ zh: String, _ ja: String, _ en: String) -> String {
    KXListingCopy.pickText(language, zh, ja, en)
}

struct GuideHomeView: View {
    @Environment(\.appLanguage) private var language
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
            await viewModel.loadGuideOS()
        }
        .refreshable {
            await viewModel.load(country: country, force: true)
            await viewModel.loadGuideOS(force: true)
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
                    GuideTodayHeader(isGuest: currentUser.isGuest)

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
                        GuideOSDashboardSection(
                            data: viewModel.guideOS,
                            isLoading: viewModel.isGuideOSLoading,
                            message: viewModel.guideOSMessage,
                            isGuest: currentUser.isGuest,
                            onOpenPlan: { router.open(.guidePlan) },
                            onOpenCalendar: { router.open(.guideCalendar) },
                            onOpenManage: { router.open(.guideManage) },
                            onOpenGoals: { router.open(.guideGoals) },
                            onOpenProfile: { router.open(.guideProfile) },
                            onOpenLife: { router.open(.guideLifePlanner) },
                            onOpenApplications: { router.open(.guideApplications) },
                            onOpenServices: { router.open(.guideServices) },
                            onOpenJourney: { key in router.open(.guideJourney(key: key)) },
                            onOpenProduct: { slug in router.open(.guideProduct(slug: slug)) },
                            onCompleteTodo: { todo in Task { await viewModel.completeGuideTodo(todo) } },
                            onCreateTodo: { content, plannedDate in
                                Task { await viewModel.createQuickTodo(content: content, plannedDate: plannedDate) }
                            }
                        )

                        GuideCategoryGrid(categories: GuideSupportCatalog.orderedCategories(from: home.categories))
                        GuideResourceEntriesSection(entries: home.resourceEntries ?? [])
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
                .buttonStyle(.plain)
                .frame(minHeight: 46)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(KXColor.separator.opacity(0.55), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(isSaving)

                Button {
                    share(article)
                } label: {
                    Label(guideText(language, "分享", "共有", "Share"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 46)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
        .contentShape(Rectangle())
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
                .buttonStyle(.plain)
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
        } catch {
            errorMessage = error.localizedDescription
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
        } catch {
            errorMessage = error.localizedDescription
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
                .buttonStyle(.plain)
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
                            .buttonStyle(.plain)
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
                .buttonStyle(.plain)
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
                        .buttonStyle(.plain)
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
            .buttonStyle(.plain)
        .contentShape(Rectangle())
            Spacer(minLength: 80)
        }
        .padding()
    }
}

private struct GuideSchoolFilterSheet: View {
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

private struct GuideHeroSection: View {
    @Environment(\.appLanguage) private var language
    let home: KaiXGuideHomeResponse
    @Binding var searchText: String
    let onSearch: (String) -> Void
    let onClear: () -> Void

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
                    Button(guideText(language, "搜索", "検索", "Search")) { onSearch(searchText) }
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
        .contentShape(Rectangle())
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
        .contentShape(Rectangle())
                }
            }
        }
        .padding(15)
        .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(KXColor.livingInk.opacity(0.06), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
    }
}

private struct GuideTodayHeader: View {
    @Environment(\.appLanguage) private var language
    let isGuest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Machi Guide OS")
            }
            .font(.caption.weight(.black))
            .tracking(1.2)
            .foregroundStyle(KXColor.livingAccent)
            Text(guideText(language, "今日", "今日", "Today"))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(KXColor.livingInk)
            Text(guideText(language, "把今天最重要的事情完成。", "今日いちばん大事なことを終わらせる。", "Finish what matters today."))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KXColor.livingMuted)
            Text(isGuest
                 ? guideText(language, "登录后同步 Todo、日历、申请和生活提醒。", "ログインするとTodo・カレンダー・申請・生活リマインダーを同期できます。", "Log in to sync todos, calendar, applications, and life reminders.")
                 : guideText(language, "Todo、日历、账单、合同、申请和路径统一到这一套行动系统。", "Todo、カレンダー、支払い、契約、申請、目標を一つの行動システムにまとめます。", "Tasks, calendar, bills, contracts, applications, and goals live in one system."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.livingSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(KXColor.livingInk.opacity(0.06), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.035), radius: 14, y: 7)
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
                title: guideText(language, "六大指南与资料", "6つのガイド・資料", "Six guides and resources"),
                subtitle: guideText(
                    language,
                    "上面推进 Todo、日历和截止日；需要查方法、学校、就职信息或服务时，从这里进入。",
                    "上ではTodo・カレンダー・期限を進め、調べ物や学校・就職情報、サービスはここから。",
                    "Act on todos, calendar, and deadlines above; find guidance, schools, careers, and services here."
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

private struct GuideResourceEntriesSection: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let entries: [KaiXGuideResourceEntryDTO]

    var body: some View {
        if !entries.isEmpty {
            GuideSectionHeader(
                title: guideText(language, "学校与公司资料库", "学校・企業データベース", "School and company libraries"),
                subtitle: guideText(
                    language,
                    "查询大学、大学院、专门学校、语言学校和适合外国人就职的日本公司",
                    "大学・大学院・専門学校・語学学校、外国人向け企業を検索",
                    "Search universities, graduate schools, vocational and language schools, and foreigner-friendly employers"
                )
            )
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
                                Text(guideText(language, "进入资料库", "データベースへ", "Open library"))
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
        .contentShape(Rectangle())
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
                        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
        .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct GuideSchoolCard: View {
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
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct GuideCompanyCard: View {
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
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct GuideCompanyPositionCard: View {
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

private struct GuideInterviewReviewCard: View {
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

private struct GuideWorkReviewCard: View {
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
        .contentShape(Rectangle())
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
