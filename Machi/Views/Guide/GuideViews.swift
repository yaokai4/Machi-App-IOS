import StoreKit
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
    // 首访一次性引导卡(I1-2):UserDefaults 持久标记 + 每次进入首页时快照。
    // 点 CTA/chip 只写标记不立刻收卡(否则 NavigationLink 推进途中卡被移除会
    // 断导航),回到首页时 onAppear 重新快照后自然消失;点 ✕ 立即收起。
    @AppStorage("hasSeenGuideIntroCard") private var hasSeenGuideIntroCard = false
    @State private var introCardActive = false

    let currentUser: UserEntity

    private var country: String {
        (regionStore.current?.countryCode ?? currentUser.country).lowercased()
    }

    private var isSearchActive: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            GuideBackground()
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { introCardActive = !hasSeenGuideIntroCard }
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
            ScrollView { KXGuideListSkeleton() }
        } else if let message = viewModel.errorMessage, viewModel.home == nil {
            ErrorStateView(message: message) {
                Task { await viewModel.load(country: country, force: true) }
            }
        } else if viewModel.isComingSoon {
            GuideComingSoonView(empty: viewModel.home?.emptyState)
        } else if let home = viewModel.home {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let message = viewModel.errorMessage, !message.isEmpty {
                        GuideInlineStatus(message: message)
                    }

                    // 首页顺序(I1-1):AI hero 置顶 → JLPT 一等卡 → 商城板块 →
                    // 指南宫格(学校/公司库并入)→ 库搜索紧凑条沉底。搜索时上方
                    // 区块整体让位,但搜索条保持同一结构位(否则 TextField 身份
                    // 变化会在首个字符后掉键盘),结果紧随其后。
                    if !isSearchActive {
                        if introCardActive {
                            GuideIntroCard(
                                onDismiss: {
                                    hasSeenGuideIntroCard = true
                                    withAnimation(.snappy(duration: 0.25)) { introCardActive = false }
                                },
                                onConsumed: { hasSeenGuideIntroCard = true }
                            )
                        }

                        GuideAIHero()

                        // JLPT 一等卡:付费漏斗的首屏入口(倒计时 + streak + 定级 CTA)。
                        GuideJLPTHomeCard()

                        // 商城板块(2026-07 商城开门):会员/商城双入口 + 精选商品卡。
                        GuideStoreSection()

                        // 指南宫格:六大指南 + 学校库/公司库(自一等双卡降级并入,入口不删)。
                        GuideCategoryGrid(
                            categories: GuideSupportCatalog.orderedCategories(from: home.categories),
                            showsLibraryEntries: true
                        )
                    }

                    GuideLibrarySearchBar(
                        searchText: $viewModel.searchText,
                        placeholder: home.hero.searchPlaceholder,
                        quickTags: home.hero.quickTags
                    )

                    if isSearchActive {
                        GuideSearchResultsSection(
                            isSearching: viewModel.isSearching,
                            articles: viewModel.searchResults,
                            schools: viewModel.schoolResults,
                            companies: viewModel.companyResults,
                            products: viewModel.productResults,
                            faq: viewModel.faqResults,
                            journeys: viewModel.journeyResults
                        )
                    }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, 10)
                .guideBottomInset()
                .kxReadableWidth()
            }
        } else {
            ScrollView { KXGuideListSkeleton() }
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
                ScrollView { KXGuideListSkeleton() }
            } else if let errorMessage, !hasLoadedContent {
                ErrorStateView(message: errorMessage) {
                    Task { await load() }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: KXSpacing.lg) {
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
            HStack(alignment: .top, spacing: KXSpacing.md) {
                Image(systemName: GuideCopy.symbol(for: category?.icon))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(KXColor.livingAccent)
                    .frame(width: 48, height: 48)
                    .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
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
                    .padding(KXSpacing.md)
                    .background(KXColor.livingSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
            }
        }
        .padding(18)
        .kxGlassSurface(radius: KXRadius.hero, elevated: true)
    }

    @ViewBuilder
    private var subCategoryTabs: some View {
        let subs = category?.subCategories ?? []
        if !subs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KXSpacing.sm) {
                    GuidePillButton(title: guideText(language, "全部", "すべて", "All"), isSelected: selectedSubCategory.isEmpty) {
                        selectedSubCategory = ""
                    }
                    ForEach(subs) { sub in
                        GuidePillButton(title: sub.title, isSelected: selectedSubCategory == sub.key) {
                            selectedSubCategory = sub.key
                        }
                    }
                }
                .padding(.vertical, KXSpacing.xxs)
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
        HStack(spacing: KXSpacing.sm) {
            KXSpinner(size: 14, lineWidth: 2)
            Text(guideText(language, "正在更新内容", "内容を更新しています", "Updating content"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, KXSpacing.md)
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
            .padding(.horizontal, KXSpacing.md)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.heat.opacity(0.08), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
    }
}

struct GuideArticleDetailView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var response: KaiXGuideArticleDetailResponse?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isMarkingRead = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?
    // #9: live reading progress. `scrollProgress` (0…100) is driven by the scroll
    // offset; `reportedProgress` remembers the last value pushed to the server so
    // we only PATCH on meaningful (10%+) jumps, throttled.
    @State private var scrollProgress: Int = 0
    @State private var reportedProgress: Int = 0
    @State private var lastProgressReport: Date = .distantPast

    let slug: String
    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }
    private var isSignedIn: Bool { (KaiXBackend.token?.isEmpty == false) }

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else if isLoading {
                ScrollView { KXGuideListSkeleton() }
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) {
                    Task { await load() }
                }
            } else if let article = response?.article {
                GeometryReader { outer in
                    ScrollView {
                        VStack(alignment: .leading, spacing: KXSpacing.lg) {
                            articleHeader(article)
                            articleTrustPanel(article)
                            articleActionBar(article)
                            articleBody(article)
                            GuideNotePanel(text: guideText(language, "本内容由 \(article.authorName) 整理，仅供参考。涉及签证、入管、考试等官方流程时，请同时以官方最新公告为准。", "本コンテンツは \(article.authorName) が整理した参考情報です。ビザ、入管、試験などの公式手続きは必ず最新の公式発表も確認してください。", "This content was curated by \(article.authorName) for reference only. For visas, immigration, exams, and other official processes, always check the latest official notices."))
                            if let related = response?.related, !related.isEmpty {
                                GuideArticleSection(title: guideText(language, "相关指南", "関連ガイド", "Related guides"), subtitle: nil, articles: related, compact: true)
                            }
                            // "Next step": route from this article into the matching
                            // action path so reading turns into doing.
                            GuideJourneyNextStepCard(categoryKey: article.categoryKey)
                            askAIRow(article)
                        }
                        .padding(KXSpacing.screen)
                        .guideBottomInset()
                        .background(
                            // Track how far the content has scrolled inside the
                            // named space; the min-Y (negative once scrolled) plus
                            // the viewport height tells us the read fraction.
                            GeometryReader { inner in
                                Color.clear.preference(
                                    key: GuideScrollProgressKey.self,
                                    value: readFraction(inner: inner, viewportHeight: outer.size.height)
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: GuideArticleDetailView.scrollSpace)
                    .onPreferenceChange(GuideScrollProgressKey.self) { fraction in
                        updateReadingProgress(fraction, article: article)
                    }
                    // A slim reading-progress bar pinned to the very top of the view.
                    .overlay(alignment: .top) {
                        GeometryReader { bar in
                            Capsule()
                                .fill(KXColor.accent)
                                .frame(width: bar.size.width * CGFloat(scrollProgress) / 100, height: 3)
                        }
                        .frame(height: 3)
                        .allowsHitTesting(false)
                    }
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
                    .padding(.horizontal, KXSpacing.sm)
                    .padding(.vertical, KXSpacing.xs)
                    .background(KXColor.accentSoft, in: Capsule())
                Text(article.authorName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(article.title)
                .kxScaledFont(27, relativeTo: .title2, weight: .bold)
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
        .kxGlassSurface(radius: KXRadius.hero)
    }

    /// G3: a compact provenance / freshness row — update date, verification date,
    /// and a tappable source label. When the content has passed its stale window
    /// (verifiedAt + staleAfterDays < now) a yellow "may be out of date" warning
    /// shows so users know to double-check official pages. Renders nothing when
    /// none of the fields are present (older payloads / plain editorial).
    @ViewBuilder
    private func articleTrustPanel(_ article: KaiXGuideArticleDTO) -> some View {
        let updated = GuideCopy.shortDate(article.updatedAt)
        let verified = GuideCopy.shortDate(article.verifiedAt)
        let sourceURL = GuideCopy.url(article.sourceUrl)
        let sourceLabel = (article.sourceLabel?.isEmpty == false) ? article.sourceLabel! : nil
        let hasAny = updated != nil || verified != nil || sourceURL != nil || sourceLabel != nil
        if hasAny {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                if isStale(article) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(KXColor.rankGold)
                        Text(guideText(language, "内容可能已过期，请以官方最新信息为准。", "内容が古くなっている可能性があります。最新の公式情報をご確認ください。", "This content may be out of date — check the latest official info."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KXColor.rankGold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KXColor.rankGold.opacity(0.12), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                }
                FlowLayout(spacing: 10) {
                    if let updated {
                        trustChip(icon: "calendar", text: guideText(language, "更新于 \(updated)", "更新日 \(updated)", "Updated \(updated)"))
                    }
                    if let verified {
                        trustChip(icon: "checkmark.shield", text: guideText(language, "核验于 \(verified)", "確認日 \(verified)", "Verified \(verified)"))
                    }
                    if let sourceURL {
                        Link(destination: sourceURL) {
                            HStack(spacing: 5) {
                                Image(systemName: "link").font(.caption2)
                                Text(sourceLabel ?? guideText(language, "来源", "出典", "Source"))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "arrow.up.right").kxScaledFont(9, weight: .bold)
                            }
                            .foregroundStyle(KXColor.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(KXColor.accentSoft, in: Capsule())
                        }
                    } else if let sourceLabel {
                        trustChip(icon: "text.book.closed", text: sourceLabel)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .kxGlassSurface(radius: KXRadius.lg)
        }
    }

    private func trustChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(KXColor.softBackground, in: Capsule())
    }

    /// I1-4 文章 → AI 联动:读完还有疑问,带着文章标题进 Machi AI 继续问。
    /// 文章详情只经路由推栈打开(无 sheet 形态),直接在当前栈推 AI 页。
    private func askAIRow(_ article: KaiXGuideArticleDTO) -> some View {
        Button {
            router.open(.guideAI(prompt: guideText(language,
                "我刚读了指南文章《\(article.title)》，还有一些不明白的地方想继续问。",
                "ガイド記事「\(article.title)」を読みましたが、まだ分からないところがあるので教えてください。",
                "I just read the guide \"\(article.title)\" and still have a few questions.")))
        } label: {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(guideText(language, "读完还有疑问？", "読んでも疑問が残る？", "Still have questions?"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(guideText(language, "问 Machi AI，结合你的情况继续讲", "Machi AI があなたの状況に合わせて解説", "Ask Machi AI to go deeper for your situation"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxGlassSurface(radius: KXRadius.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }

    /// True once the article is past `verifiedAt + staleAfterDays`.
    private func isStale(_ article: KaiXGuideArticleDTO) -> Bool {
        guard let days = article.staleAfterDays, days > 0,
              let verified = KXDateParsing.parse(article.verifiedAt ?? "") else { return false }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: days, to: verified) else { return false }
        return cutoff < Date()
    }

    private func articleActionBar(_ article: KaiXGuideArticleDTO) -> some View {
        let progress = max(0, min(100, article.progressPercent ?? article.readingProgress?.progressPercent ?? 0))
        let saved = article.saved == true
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
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
                .padding(.horizontal, KXSpacing.md)
                .background(KXColor.livingSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous).stroke(KXColor.separator.opacity(0.55), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                .disabled(isSaving)

                ShareLink(
                    item: URL(string: "https://machicity.com/guide/articles/\(article.slug)") ?? URL(string: "https://machicity.com")!,
                    subject: Text(article.title),
                    preview: SharePreview(article.title)
                ) {
                    Label(guideText(language, "分享", "共有", "Share"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.fullArea)
                .frame(minHeight: 46)
                .padding(.horizontal, KXSpacing.md)
                .background(KXColor.livingSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous).stroke(KXColor.separator.opacity(0.55), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
            }

            Button {
                Task { await markRead(article) }
            } label: {
                HStack {
                    if isMarkingRead {
                        ProgressView().tint(KXColor.onAccent)
                    } else {
                        Image(systemName: progress >= 95 ? "checkmark.seal.fill" : "checkmark.circle")
                    }
                    Text(progress >= 95 ? guideText(language, "已读完", "読了", "Finished") : guideText(language, "标记读完", "読了にする", "Mark as read"))
                    Spacer()
                    Text("\(progress)%")
                        .font(.caption.weight(.black))
                }
                .foregroundStyle(KXColor.onAccent)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(KXColor.accent, in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
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
        .kxGlassSurface(radius: KXRadius.card)
    }

    private func articleBody(_ article: KaiXGuideArticleDTO) -> some View {
        // markdown-lite: ## / ### headings, - / 1. lists, | tables |, **bold**,
        // [links](url). Legacy plain-paragraph articles (no markers) still render
        // as before because unmarked lines fall back to paragraphs.
        VStack(alignment: .leading, spacing: 14) {
            GuideMarkdownLite(text: (article.body ?? article.summary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .kxGlassSurface(radius: KXRadius.hero)
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

    // MARK: - #9 reading progress

    static let scrollSpace = "guide-article-scroll"

    /// Fraction (0…1) of the article that has been scrolled past. `inner.minY` in
    /// the scroll coordinate space is the content's top offset (0 at rest, more
    /// negative as it scrolls up); dividing the scrolled distance by the
    /// scrollable range gives the read fraction.
    private func readFraction(inner: GeometryProxy, viewportHeight: CGFloat) -> CGFloat {
        let contentHeight = inner.size.height
        let scrollable = contentHeight - viewportHeight
        guard scrollable > 1 else { return 1 } // shorter than the screen → fully read
        let scrolledUp = -inner.frame(in: .named(GuideArticleDetailView.scrollSpace)).minY
        return max(0, min(1, scrolledUp / scrollable))
    }

    /// Update the local progress bar and, when signed in, throttle-report to the
    /// server. We never regress the reported value and only PATCH on a 10%+ gain
    /// at most once every 4s (or immediately when the reader reaches the end).
    private func updateReadingProgress(_ fraction: CGFloat, article: KaiXGuideArticleDTO) {
        let percent = max(0, min(100, Int((fraction * 100).rounded())))
        // The stored/marked-read value is a floor — a read article stays read.
        let baseline = max(article.progressPercent ?? article.readingProgress?.progressPercent ?? 0, reportedProgress)
        let display = max(percent, baseline)
        if display != scrollProgress { scrollProgress = display }

        guard isSignedIn else { return }
        let now = Date()
        let reachedEnd = percent >= 98 && reportedProgress < 98
        let bigJump = percent - reportedProgress >= 10
        let throttled = now.timeIntervalSince(lastProgressReport) >= 4
        guard percent > reportedProgress, reachedEnd || (bigJump && throttled) else { return }

        reportedProgress = percent
        lastProgressReport = now
        Task {
            // Best-effort: a dropped progress ping is harmless, so failures are
            // swallowed (no toast, no state change).
            _ = try? await KaiXAPIClient.shared.updateGuideArticleProgress(article.slug, country: country, progressPercent: percent)
        }
    }
}

/// Carries the article scroll read-fraction up to the detail view.
private struct GuideScrollProgressKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct GuideServicesView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var userStore: UserStore
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var products: [KaiXGuideProductDTO] = []
    @State private var productType = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showMembershipSheet = false
    @State private var showWalletSheet = false
    // I1-6 币余额前置:登录态在钱包按钮上直接显示余额,「有币不知道花」的
    // 第一现场。复用 WalletStore(refreshWallet 只打 walletMe,不碰 StoreKit);
    // 游客/加载失败静默回退原文案。
    @StateObject private var walletStore = WalletStore()

    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }
    private var currentUser: UserEntity? {
        guard let id = userStore.currentUserId else { return nil }
        return userStore.usersById[id]
    }
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

    /// Zero-friction lead-in SKUs shown first — a store whose first shelf is
    /// free builds trust before it asks for money.
    private var freeProducts: [KaiXGuideProductDTO] { products.filter { $0.isFree } }
    private var paidProducts: [KaiXGuideProductDTO] { products.filter { !$0.isFree } }
    /// Total member savings across the visible paid SKUs — concrete yen
    /// beats "开通会员" copy (会员价值条 uses this number).
    private var memberSavings: Int {
        paidProducts.reduce(0) { total, p in
            guard let member = p.memberPrice, member > 0, p.price > member else { return total }
            return total + (p.price - member)
        }
    }
    private var isMember: Bool { currentUser?.isVerifiedMember == true }

    var body: some View {
        ZStack {
            GuideBackground()
            if country != "jp" {
                GuideComingSoonView()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        servicesHeader
                        myShelfRow
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: KXSpacing.sm) {
                                ForEach(filters, id: \.0) { value, title in
                                    GuidePillButton(title: title, isSelected: productType == value) {
                                        productType = value
                                    }
                                }
                            }
                            .padding(.vertical, KXSpacing.xxs)
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
                            if !freeProducts.isEmpty {
                                storeSectionTitle(guideText(language, "免费领取", "無料で受け取る", "Free to claim"), icon: "gift.fill")
                                LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                                    ForEach(freeProducts) { product in
                                        GuideProductCard(product: product)
                                    }
                                }
                            }
                            if !paidProducts.isEmpty {
                                if !isMember && memberSavings > 0 {
                                    memberValueStrip
                                }
                                storeSectionTitle(guideText(language, "备考与申请资料", "対策・出願資料", "Prep & application resources"), icon: "books.vertical.fill")
                                LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                                    ForEach(paidProducts) { product in
                                        GuideProductCard(product: product)
                                    }
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
        .task {
            guard KaiXBackend.token?.isEmpty == false else { return }
            await walletStore.refreshWallet()
        }
        .sheet(isPresented: $showWalletSheet) {
            NavigationStack { WalletView() }
        }
        .sheet(isPresented: $showMembershipSheet) {
            if let currentUser {
                NavigationStack { MembershipView(currentUser: currentUser) }
            }
        }
    }

    private var servicesHeader: some View {
        KXCard(padding: 16, radius: 22) {
            HStack(alignment: .top, spacing: KXSpacing.md) {
                GuideIconBubble(icon: "shippingbox.fill", color: KXColor.heat)
                VStack(alignment: .leading, spacing: 5) {
                    Text(guideText(language, "商城", "ストア", "Store"))
                        .font(.title2.weight(.bold))
                    Text(guideText(language, "JLPT 备考、留学申请、就职求职的资料与服务", "JLPT 対策・留学出願・就職活動の資料とサービス", "Resources and services for JLPT prep, applications, and careers"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(guideText(language, "支持 Machi 币或 App 内购买；服务类可提交预约咨询。", "Machi コインまたはアプリ内購入に対応。サービスは予約相談できます。", "Pay with Machi Coins or in-app purchase; services accept appointment inquiries."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Compact row: my purchased library + wallet balance/top-up.
    private var myShelfRow: some View {
        HStack(spacing: 10) {
            Button {
                router.open(.guideMyLibrary)
            } label: {
                Label(guideText(language, "我的资料库", "マイライブラリ", "My library"), systemImage: "books.vertical")
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(KXColor.accentSoft, in: Capsule())
                    .foregroundStyle(KXColor.accent)
            }
            .buttonStyle(.fullArea)
            .contentShape(Rectangle())
            Button {
                showWalletSheet = true
            } label: {
                Label(walletButtonTitle, systemImage: "circle.hexagongrid.fill")
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.orange.opacity(0.14), in: Capsule())
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.fullArea)
            .contentShape(Rectangle())
        }
    }

    /// 余额拿到了就直接亮在按钮上;游客 / walletMe 失败时回退原文案。
    private var walletButtonTitle: String {
        if let balance = walletStore.wallet?.balancePoints {
            return guideText(language, "Machi 币 · \(balance)", "Machi コイン · \(balance)", "Machi Coins · \(balance)")
        }
        return guideText(language, "Machi 币钱包", "Machi コイン", "Machi Coins")
    }

    /// 会员价值条 — a value frame ("this page saves you ¥N"), deliberately NOT
    /// a top-of-page subscription pitch: contextual savings copy converts,
    /// cold paywalls on a young store read as a cash grab.
    private var memberValueStrip: some View {
        Button {
            if currentUser != nil { showMembershipSheet = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(KXColor.accent)
                Text(guideText(language,
                    "会员享会员价，本页合计可省 ¥\(memberSavings)",
                    "会員価格でこのページ合計 ¥\(memberSavings) お得",
                    "Members save ¥\(memberSavings) on this page"))
                    .font(.footnote.weight(.bold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }

    private func storeSectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func load() async {
        guard country == "jp" else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        Task { await KaiXAPIClient.shared.funnelEvent("store_view", entityType: "guide_store", entityId: productType.isEmpty ? "all" : productType) }
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
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(alignment: .top, spacing: KXSpacing.md) {
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
                    // Neutral entitlement copy only — Apple 3.1.1 forbids
                    // steering users to purchase outside the app.
                    Text(guideText(language, "非会员可查看预览，购买或开通会员后可查看完整内容。", "非会員はプレビューを確認できます。購入または会員登録後に全文を閲覧できます。", "Non-members can view previews. Purchase or activate membership to view the full content."))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KXColor.accent)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                }
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(guideText(language, "搜索会员资料", "会員資料を検索", "Search member resources"), text: $keyword)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await load() } }
                }
                .padding(KXSpacing.md)
                .background(KXColor.softBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KXSpacing.sm) {
                ForEach(filters, id: \.0) { value, title in
                    GuidePillButton(title: title, isSelected: categoryKey == value) {
                        categoryKey = value
                    }
                }
            }
            .padding(.vertical, KXSpacing.xxs)
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
    @EnvironmentObject private var userStore: UserStore
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var product: KaiXGuideProductDTO?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?
    @State private var showTopupSheet = false
    @State private var showMembershipSheet = false
    /// I1-4 购前咨询:sheet 内打开 Machi AI 并预填商品名(详情页也会以 sheet
    /// 形态出现——模考推荐卡等——所以不能走 tab 路由推栈)。
    @State private var showAIConsult = false
    /// StoreKit product for single-product IAP purchase, loaded when the
    /// server product carries an `appleProductId` (machi_guide_* convention).
    @State private var storeKitProduct: Product?

    let slug: String
    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }

    /// Current signed-in member state, read from the shared user store. Used to
    /// decide whether the member price shows as a "you save" line (member) or a
    /// tappable upsell (non-member).
    private var currentUser: UserEntity? {
        guard let id = userStore.currentUserId else { return nil }
        return userStore.usersById[id]
    }
    private var isMember: Bool {
        currentUser?.isVerifiedMember == true || product?.access?.memberUnlocked == true
    }

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
                            previewPanel(preview, product: product)
                        }
                        productDescription(product)
                        aiConsultRow(product)
                        // BE4: user reviews (star summary + distribution + list +
                        // write-review sheet for buyers/members). Uses slug — the
                        // review endpoints accept id-or-slug like the detail route.
                        GuideProductReviewsSection(productRef: product.slug)
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
        .sheet(isPresented: $showMembershipSheet, onDismiss: { Task { await load() } }) {
            if let currentUser {
                NavigationStack { MembershipView(currentUser: currentUser) }
            }
        }
        .sheet(isPresented: $showAIConsult) {
            if let currentUser, let product {
                GuideAIChatView(currentUser: currentUser, initialPrompt: aiConsultPrompt(product))
            }
        }
    }

    /// I1-4 购前咨询入口:把「不确定适不适合我」的犹豫引到 Machi AI(预填商品名)。
    @ViewBuilder
    private func aiConsultRow(_ product: KaiXGuideProductDTO) -> some View {
        if currentUser != nil {
            Button {
                showAIConsult = true
            } label: {
                HStack(spacing: KXSpacing.md) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guideText(language, "购买前想先问问？", "購入前に相談したい？", "Questions before you buy?"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(guideText(language, "问 Machi AI 这份内容适不适合你", "この内容が自分に合うか Machi AI に聞く", "Ask Machi AI if this is right for you"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kxGlassSurface(radius: KXRadius.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.fullArea)
            .contentShape(Rectangle())
        }
    }

    private func aiConsultPrompt(_ product: KaiXGuideProductDTO) -> String {
        guideText(language,
            "我在看《\(product.title)》，帮我介绍一下它的内容和适合人群，我在考虑要不要入手。",
            "「\(product.title)」を見ています。内容と対象者を教えてください。入手を検討中です。",
            "I'm looking at \"\(product.title)\" — can you walk me through what it covers and who it's for? I'm deciding whether to get it.")
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

                // #1: member price — strikethrough original + member price for
                // members; a tappable "会员价 ¥xx" upsell for everyone else.
                GuideMemberPriceRow(
                    product: product,
                    isMember: isMember,
                    language: language,
                    onUpgrade: { if currentUser != nil { showMembershipSheet = true } }
                )

                HStack(spacing: 10) {
                    Text(price)
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 0)
                    if productNotReady(product) {
                        // C-1 deliverable_ready=false:交付物未就绪,所有付费购买
                        // 路径统一收成一枚置灰 CTA(服务端同步拒绝 PRODUCT_NOT_READY)。
                        Text(guideText(language, "内容准备中", "準備中", "Coming soon"))
                            .font(.subheadline.weight(.bold))
                            .frame(height: 40)
                            .padding(.horizontal, 18)
                            .background(Color.secondary.opacity(0.20), in: Capsule())
                            .foregroundStyle(Color.secondary)
                    } else if !hasDirectPurchasePath(product) {
                        // Hide the legacy "coming soon" chip once the product has a
                        // live purchase path (IAP and/or coins) — showing a disabled
                        // CTA next to working buy buttons reads as contradictory.
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
                }
                // Single-product IAP: primary buy button with the StoreKit
                // localized price (server verify → entitlement, see
                // productIapAction). Coins purchase stays available below.
                if let sk = storeKitProduct, product.access?.canAccess != true, !product.isService, !productNotReady(product) {
                    Button {
                        Task { await productIapAction(product) }
                    } label: {
                        Text(guideText(language, "\(sk.displayPrice) 购买", "\(sk.displayPrice) で購入", "Buy for \(sk.displayPrice)"))
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(KXColor.accent, in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .disabled(isSubmitting)
                }
                if product.canBuyWithPoints == true && product.access?.canAccess != true && !productNotReady(product) {
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

    /// True when an unowned paid digital product has at least one live
    /// purchase path (single-product IAP or Machi Coins) — the legacy
    /// "coming soon" main CTA is hidden in that case.
    private func hasDirectPurchasePath(_ product: KaiXGuideProductDTO) -> Bool {
        guard !product.isService, !product.isFree, product.access?.canAccess != true else { return false }
        return storeKitProduct != nil || product.canBuyWithPoints == true
    }

    /// C-1 deliverable_ready=false → 付费购买 CTA 置灰「内容准备中」。与服务端
    /// 拒绝口径一致:免费领取与人工服务不受影响,已解锁的买家照常看内容。
    private func productNotReady(_ product: KaiXGuideProductDTO) -> Bool {
        !product.deliverableReady && !product.isService && !product.isFree && product.access?.canAccess != true
    }

    /// Single-product Apple IAP purchase. Server verify is the source of
    /// truth: the transaction is finished ONLY after
    /// /api/payments/apple/guide-verify confirmed the entitlement; a verify
    /// failure leaves it unfinished for IAPTransactionObserver to retry, and
    /// the user is told NOT to buy again.
    private func productIapAction(_ product: KaiXGuideProductDTO) async {
        guard let sk = storeKitProduct, !isSubmitting else { return }
        guard KaiXBackend.token != nil, let user = currentUser else {
            toastMessage = guideText(language, "请登录后购买。", "ログインして購入してください。", "Please log in to purchase.")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        Task { await KaiXAPIClient.shared.funnelEvent("purchase_start", entityType: "guide_product", entityId: product.slug, props: ["method": "iap"]) }
        let result: Product.PurchaseResult
        do {
            var options: Set<Product.PurchaseOption> = []
            if let token = MembershipStore.appAccountToken(for: user) { options.insert(.appAccountToken(token)) }
            result = try await sk.purchase(options: options)
        } catch {
            toastMessage = error.kaixUserMessage
            return
        }
        switch result {
        case .success(let verification):
            let transaction: StoreKit.Transaction
            switch verification {
            case .verified(let t), .unverified(let t, _):
                transaction = t
            }
            do {
                _ = try await KaiXAPIClient.shared.verifyAppleGuidePurchase(
                    productId: transaction.productID,
                    transactionId: String(transaction.id),
                    originalTransactionId: String(transaction.originalID),
                    signedTransaction: verification.jwsRepresentation,
                    environment: transaction.environment.rawValue
                )
                await transaction.finish()
                Task { await KaiXAPIClient.shared.funnelEvent("purchase_success", entityType: "guide_product", entityId: product.slug, props: ["method": "iap"]) }
                // I2-7 付费成功是最强好评时刻(版本内一次的总闸在服务里)。
                ReviewPromptService.shared.notePurchaseSuccess()
                toastMessage = guideText(language, "购买成功。", "購入が完了しました。", "Purchase complete.")
                await load()
            } catch {
                // Paid but not yet credited — never say "failed, retry": the
                // observer re-verifies the unfinished transaction automatically.
                toastMessage = guideText(language,
                    "已完成支付，正在确认订单，请勿重复购买。稍后会自动到账。",
                    "支払いは完了しています。注文を確認中のため、再購入しないでください。まもなく自動で反映されます。",
                    "Payment completed — confirming your order, please don't buy again. It will unlock automatically.")
            }
        case .pending:
            toastMessage = guideText(language,
                "购买等待批准中，批准后会自动到账。",
                "購入は承認待ちです。承認後に自動で反映されます。",
                "Purchase pending approval — it will unlock automatically once approved.")
        case .userCancelled:
            break
        @unknown default:
            break
        }
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
        Task { await KaiXAPIClient.shared.funnelEvent("purchase_start", entityType: "guide_product", entityId: product.slug, props: ["method": "wallet"]) }
        do {
            let resp = try await KaiXAPIClient.shared.purchaseGuideProductWithWallet(product.slug)
            Task { await KaiXAPIClient.shared.funnelEvent("purchase_success", entityType: "guide_product", entityId: product.slug, props: ["method": "wallet"]) }
            // I2-7 币购成功同 IAP:付费拿到内容的当口触发评分提示。
            ReviewPromptService.shared.notePurchaseSuccess()
            toastMessage = resp.message ?? guideText(language, "购买成功。", "購入が完了しました。", "Purchase complete.")
            await load()
        } catch {
            // Only route to top-up when the cause is genuinely insufficient
            // balance (402 / insufficient_*). Any other failure (network, server
            // error, already-owned) must surface its real message instead of a
            // misleading "top up" prompt.
            if let api = error as? KaiXAPIError,
               api.error.code == "http_402" || api.error.code.localizedCaseInsensitiveContains("insufficient") {
                showTopupSheet = true
            } else {
                toastMessage = error.kaixUserMessage
            }
        }
    }

    private func productDescription(_ product: KaiXGuideProductDTO) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
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
            // Pre-purchase notice: the refund policy is a paid-SKU disclosure
            // requirement (server backfills a trilingual default; admin can
            // override per SKU). Rendered before purchase, not after.
            if let policy = product.refundPolicy, !policy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().opacity(0.25)
                VStack(alignment: .leading, spacing: 6) {
                    Label(guideText(language, "购前须知 · 退款政策", "購入前のご確認 · 返金ポリシー", "Before you buy · Refund policy"), systemImage: "info.circle")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(localizedRefundPolicyLine(policy))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .kxGlassSurface(radius: KXRadius.hero)
    }

    /// The server's default refund policy is one trilingual blob (zh / ja / en
    /// on separate lines). Pick the viewer's language line when the blob has
    /// that shape; otherwise show the operator's custom text as-is.
    private func localizedRefundPolicyLine(_ policy: String) -> String {
        let lines = policy.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 3 else { return policy }
        return guideText(language, lines[0], lines[1], lines[2])
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
    private func previewPanel(_ preview: String, product: KaiXGuideProductDTO) -> some View {
        let locked = product.hasPurchaseContent == true
        KXCard(padding: 18, radius: 22) {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                Label(guideText(language, "预览内容", "プレビュー", "Preview"), systemImage: "lock.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if locked {
                    // Neutral entitlement copy only — Apple 3.1.1 forbids
                    // steering users to purchase outside the app. When the
                    // item can be bought with Machi Coins, offer that
                    // in-app path right here.
                    Text(guideText(language, "购买或开通会员后可查看完整内容。", "購入または会員登録後に全文を閲覧できます。", "Purchase or activate membership to view the full content."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if product.canBuyWithPoints == true, !productNotReady(product) {
                        Button {
                            Task { await productPointsAction(product) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.orange)
                                Text(pointsCTALabel(product))
                                    .font(.subheadline.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(KXColor.accentSoft, in: Capsule())
                            .foregroundStyle(KXColor.accent)
                        }
                        .buttonStyle(.fullArea)
                        .contentShape(Rectangle())
                        .disabled(isSubmitting)
                    }
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
            Task { await KaiXAPIClient.shared.funnelEvent("sku_view", entityType: "guide_product", entityId: slug) }
            // Load the StoreKit product for single-product IAP when the server
            // product carries an IAP id and isn't owned yet. Failure is benign
            // (no IAP button; coins purchase still works).
            let iapId = [response.product.appleProductId, response.product.iosIapProductId]
                .compactMap { $0 }.first { !$0.isEmpty } ?? ""
            if !iapId.isEmpty, response.product.access?.canAccess != true {
                storeKitProduct = try? await Product.products(for: [iapId]).first
            } else {
                storeKitProduct = nil
            }
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
        VStack(spacing: KXSpacing.lg) {
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
                    .foregroundStyle(KXColor.onAccent)
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
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
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
            FlowLayout(spacing: KXSpacing.sm) {
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

/// 库搜索紧凑条(I1-1):自「浏览资料库」大 hero 压缩而来,沉底作为资料库
/// 检索入口。搜索功能不动 —— 仍由 host(`GuideHomeView`)对绑定的
/// `searchText` 做 debounce `.onChange`,这里只改绑定值。
private struct GuideLibrarySearchBar: View {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "book.pages")
                Text(guideText(language, "搜资料库", "資料庫を検索", "Search the library"))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(KXColor.livingAccent)

            HStack(spacing: KXSpacing.sm) {
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
                    .accessibilityLabel(guideOSText(language, "清除", "クリア", "Clear"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                    .stroke(KXColor.livingInk.opacity(0.08), lineWidth: 0.8)
            }

            if !quickTags.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(quickTags, id: \.self) { tag in
                        Button {
                            searchText = tag
                        } label: {
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(KXColor.livingInk.opacity(0.74))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(KXColor.livingSurface, in: Capsule())
                                .overlay(Capsule().stroke(KXColor.livingInk.opacity(0.06), lineWidth: 0.8))
                        }
                        .buttonStyle(.fullArea)
                        .contentShape(Capsule())
                    }
                }
            }
        }
        .padding(15)
        .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous).stroke(KXColor.livingInk.opacity(0.06), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
    }
}

private struct GuideSearchResultsSection: View {
    @Environment(\.appLanguage) private var language
    let isSearching: Bool
    let articles: [KaiXGuideArticleDTO]
    let schools: [KaiXGuideSchoolDTO]
    let companies: [KaiXGuideCompanyDTO]
    let products: [KaiXGuideProductDTO]
    let faq: [KaiXGuideFaqDTO]
    let journeys: [KaiXGuideJourneyDTO]

    private var total: Int {
        articles.count + schools.count + companies.count + products.count + faq.count + journeys.count
    }

    var body: some View {
        GuideSectionHeader(
            title: guideText(language, "搜索结果", "検索結果", "Search results"),
            subtitle: isSearching
                ? guideText(language, "正在查找学校、公司、资料、FAQ 和指南路径", "学校・会社・資料・FAQ・ガイドパスを検索中", "Searching schools, companies, resources, FAQ, and paths")
                : guideText(language, "共 \(total) 条 · Guide 所有内容都已包含", "合計 \(total) 件 · Guide 内の全コンテンツを含む", "\(total) total · all Guide content included")
        )
        if isSearching {
            LoadingView()
        } else if total == 0 {
            EmptyStateView(title: guideText(language, "没有找到相关内容", "関連内容が見つかりません", "No matching content"), subtitle: guideText(language, "换个关键词试试，可以搜学校、公司、资料、FAQ、路径和任意指南内容。", "別のキーワードを試してください。学校、会社、資料、FAQ、パス、ガイド内容で検索できます。", "Try another keyword. Search schools, companies, resources, FAQ, paths, and guide content."), systemImage: "magnifyingglass")
        } else {
            if !schools.isEmpty {
                groupLabel(icon: "graduationcap.fill", title: guideText(language, "学校", "学校", "Schools"), count: schools.count)
                ForEach(schools) { GuideSchoolCard(school: $0) }
            }
            if !companies.isEmpty {
                groupLabel(icon: "building.2.fill", title: guideText(language, "就职公司", "就職企業", "Companies"), count: companies.count)
                ForEach(companies) { GuideCompanyCard(company: $0) }
            }
            if !journeys.isEmpty {
                groupLabel(icon: "map.fill", title: guideText(language, "行动路径", "アクションパス", "Action paths"), count: journeys.count)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(journeys) { journey in
                        GuideSearchJourneyCard(journey: journey)
                    }
                }
            }
            if !products.isEmpty {
                groupLabel(icon: "shippingbox.fill", title: guideText(language, "资料与服务", "資料・サービス", "Resources & services"), count: products.count)
                ForEach(products) { product in
                    GuideProductCard(product: product)
                }
            }
            if !articles.isEmpty {
                groupLabel(icon: "doc.text.fill", title: guideText(language, "指南文章", "ガイド記事", "Guide articles"), count: articles.count)
                ForEach(articles) { GuideArticleCard(article: $0, compact: true) }
            }
            if !faq.isEmpty {
                groupLabel(icon: "questionmark.bubble.fill", title: "FAQ", count: faq.count)
                VStack(spacing: 9) {
                    ForEach(faq) { item in
                        GuideSearchFAQCard(item: item)
                    }
                }
            }
        }
    }

    private func groupLabel(icon: String, title: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.livingAccent)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(KXColor.livingInk)
            Text("\(count)")
                .font(.caption2.weight(.black))
                .foregroundStyle(KXColor.livingAccent)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(KXColor.livingAccentSoft, in: Capsule())
            Spacer(minLength: 0)
        }
        .padding(.top, KXSpacing.xs)
    }
}

private struct GuideSearchJourneyCard: View {
    @EnvironmentObject private var router: AppRouter
    let journey: KaiXGuideJourneyDTO

    var body: some View {
        GuideJourneyCard(journey: journey, doneCount: 0) {
            router.open(.guideJourney(key: journey.key))
        }
    }
}

private struct GuideSearchFAQCard: View {
    let item: KaiXGuideFaqDTO

    var body: some View {
        DisclosureGroup {
            Text(item.answer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 10) {
                GuideIconBubble(icon: "questionmark.bubble.fill", color: KXColor.rankGold, size: 36)
                Text(item.question)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}

private struct GuideCategoryGrid: View {
    @Environment(\.appLanguage) private var language
    let categories: [KaiXGuideCategoryDTO]
    /// I1-1:学校库/公司库自首页一等双卡降级并入宫格 —— 入口保留,权重下调。
    var showsLibraryEntries = false

    var body: some View {
        if !categories.isEmpty || showsLibraryEntries {
            Divider()
                .padding(.top, KXSpacing.xs)
            GuideSectionHeader(
                title: showsLibraryEntries
                    ? guideText(language, "指南与资料库", "ガイド・資料庫", "Guides & libraries")
                    : guideText(language, "六大指南", "6つのガイド", "Guide categories"),
                subtitle: showsLibraryEntries
                    ? guideText(
                        language,
                        "按目标进入系统化指南，学校库和公司库也在这里。",
                        "目的別ガイドに加えて、学校・企業データベースもこちら。",
                        "Structured guides by goal, plus the school and company libraries."
                    )
                    : guideText(
                        language,
                        "按目标进入系统化指南，先看路径，再查资料和服务。",
                        "目的別にガイドを確認し、流れ・資料・サービスへ進みます。",
                        "Browse structured guides by goal, then open resources and services."
                    )
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: KXSpacing.md), GridItem(.flexible(), spacing: KXSpacing.md)], spacing: KXSpacing.md) {
                ForEach(categories) { category in
                    GuideCategoryCard(category: category)
                }
                if showsLibraryEntries {
                    GuideLibraryGridTile(
                        icon: "graduationcap.fill",
                        tint: KXColor.rankSky,
                        title: guideText(language, "日本学校库", "学校データベース", "School library"),
                        subtitle: guideText(language, "大学、大学院、专门学校、语言学校", "大学・大学院・専門・語学", "Universities, grad, vocational, language"),
                        route: .guideSchools,
                        identifier: "guide.library.schools"
                    )
                    GuideLibraryGridTile(
                        icon: "building.2.fill",
                        tint: KXColor.rankTeal,
                        title: guideText(language, "就职公司库", "就職企業データベース", "Company library"),
                        subtitle: guideText(language, "外国人友好企业、签证支持与真实评价", "外国人歓迎・ビザ支援・口コミ", "Foreigner-friendly, visa support, reviews"),
                        route: .guideCompanies,
                        identifier: "guide.library.companies"
                    )
                }
            }
        }
    }
}

/// 宫格里的学校库/公司库入口:与 GuideCategoryCard 同一视觉节奏(icon bubble +
/// 标题 + 两行描述),稳定 accessibilityIdentifier 供 UI 测试按标识定位。
private struct GuideLibraryGridTile: View {
    @EnvironmentObject private var router: AppRouter
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let route: KXRoute
    let identifier: String

    var body: some View {
        Button {
            router.open(route)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                GuideIconBubble(icon: icon, color: tint, size: 40)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            .padding(KXSpacing.md)
            .kxGlassSurface(radius: KXRadius.hero)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
        .accessibilityIdentifier(identifier)
    }
}

/// Machi AI hero —— 「Machi AI」Tab 的第一屏主角,让 Tab 名和落点名实相符。
/// 大号品牌标 + 一句三语价值主张 + 常驻「输入框」样式的 CTA + 场景化快捷问题
/// chip。主 CTA 进入空聊天页;场景 chip 经 `.guideAI(prompt:)` 载荷把问题预填进
/// 「原来可以这么问」的示范作用;真正的一键提问 chip 在聊天页里)。
/// Never references any provider/model — to the user this is Machi's own
/// assistant. 不带「Beta」标:AI 就是这个 Tab 的正主,不是实验品。
private struct GuideAIHero: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    /// 静态三语场景问题:新用户 5 秒内理解「这里可以问什么」。
    private var starterQuestions: [String] {
        [
            guideText(language, "留学签证怎么续？", "留学ビザの更新方法は？", "How do I renew my student visa?"),
            guideText(language, "东京哪里租房便宜？", "東京で家賃が安いエリアは？", "Where is rent cheaper in Tokyo?"),
            guideText(language, "日企面试怎么准备？", "日本企業の面接対策は？", "How do I prep for interviews at Japanese firms?")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: KXSpacing.md) {
                MachiAIMark(size: 50)
                    .shadow(color: KXColor.livingAccent.opacity(0.26), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Machi AI")
                        .kxScaledFont(22, relativeTo: .title3, weight: .bold, design: .rounded)
                        .foregroundStyle(KXColor.livingInk)
                    Text(guideText(language,
                                   "在日生活、升学、就职，有问题先问它。",
                                   "日本での生活・進学・就職、まずここで質問。",
                                   "Life, study, and work in Japan — ask here first."))
                        .font(.footnote)
                        .foregroundStyle(KXColor.livingMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // 主入口横向铺满内容区，消除无意义留白；浅色渐变与圆角矩形让它保持
            // 轻盈，并和下方胶囊形快捷问题维持清楚的主次层级。
            Button {
                router.open(.guideAI(prompt: nil), in: .guide)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guideText(language, "进入 Machi AI", "Machi AI を開く", "Open Machi AI"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.livingAccent)

                        Text(guideText(language, "开始新对话", "新しい会話を始める", "Start a new chat"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(KXColor.livingMuted)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.onTint(KXColor.livingAccent))
                        .frame(width: 34, height: 34)
                        .background(KXColor.livingAccent, in: Circle())
                        .accessibilityHidden(true)
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(
                    LinearGradient(
                        colors: [
                            KXColor.livingAccent.opacity(0.07),
                            KXColor.livingAccent.opacity(0.13),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(KXColor.livingAccent.opacity(0.22), lineWidth: 0.9)
                )
                .shadow(color: KXColor.livingAccent.opacity(0.09), radius: 9, y: 4)
            }
            .buttonStyle(.fullArea)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .accessibilityIdentifier("guide.ai.entry")
            .accessibilityLabel(guideText(language, "进入 Machi AI", "Machi AI を開く", "Open Machi AI"))

            // 场景化快捷问题:点击进入对话页并预填问题。tonal 胶囊,与主 CTA 同一色系。
            FlowLayout(spacing: 7) {
                ForEach(starterQuestions, id: \.self) { question in
                    Button {
                        router.open(.guideAI(prompt: question), in: .guide)
                    } label: {
                        Text(question)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(KXColor.livingAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(KXColor.livingAccentSoft, in: Capsule())
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Capsule())
                }
            }
        }
        .padding(KXSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous)
                .stroke(KXColor.livingInk.opacity(0.06), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
    }
}

/// JLPT 一等卡(I1-1)— 首页付费漏斗的第一入口:距下一场考试倒计时 +
/// 打卡 streak + 「30 秒定级」主 CTA。倒计时走公开 exam-dates 端点,
/// streak 仅登录态拉取;任一失败静默降级为纯入口卡,绝不阻塞首页。
private struct GuideJLPTHomeCard: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @State private var countdown: KaiXJLPTCountdown?
    @State private var streak: KaiXJLPTStreak?
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .center) {
                JLPTEyebrow(text: "Machi Guide · JLPT")
                Spacer(minLength: 0)
                if let streak, (streak.currentStreak ?? 0) > 0 {
                    JLPTStreakBadge(streak: streak, compact: true)
                }
            }

            Button {
                router.open(.guideCategory(categoryKey: "jlpt"))
            } label: {
                HStack(spacing: KXSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guideText(language, "JLPT 备考专区", "JLPT 対策センター", "JLPT prep center"))
                            .kxScaledFont(22, relativeTo: .title3, weight: .bold, design: .rounded)
                            .foregroundStyle(KXColor.livingInk)
                        Text(guideText(language, "定级 · 练习 · 模考 · 错题本", "レベル判定・演習・模試・間違いノート", "Placement, practice, mock exams, review"))
                            .font(.footnote)
                            .foregroundStyle(KXColor.livingMuted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.livingMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.fullArea)
            .accessibilityIdentifier("guide.jlpt.card")

            if let countdown {
                JLPTCountdownBar(countdown: countdown)
            }

            NavigationLink {
                GuideJLPTPlacementView()
            } label: {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.subheadline.weight(.bold))
                    Text(guideText(language, "30 秒测水平，领备考等级", "30秒でレベル判定", "Find your level in 30 seconds"))
                        .font(.subheadline.weight(.bold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(KXColor.onAccent)
                .padding(.vertical, 14)
                .padding(.horizontal, KXSpacing.lg)
                .background(KXColor.livingAccent, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .shadow(color: KXColor.livingAccent.opacity(0.24), radius: 10, y: 4)
            }
            .buttonStyle(KXPressableStyle(scale: 0.97))
            .accessibilityIdentifier("guide.jlpt.placement")
        }
        .padding(KXSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous)
                .stroke(KXColor.livingInk.opacity(0.06), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
        .task { await load() }
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        if let resp = try? await KaiXAPIClient.shared.jlptExamDates() {
            countdown = resp.countdown
        }
        // streak 是登录态资源(游客 401),不请求即不闪错。
        guard KaiXBackend.token?.isEmpty == false else { return }
        if let resp = try? await KaiXAPIClient.shared.jlptStreak() {
            streak = KaiXJLPTStreak(
                currentStreak: resp.currentStreak,
                longestStreak: resp.longestStreak,
                todayDone: resp.todayDone,
                totalDays: resp.totalDays,
                last7days: resp.last7days
            )
        }
    }
}

/// 首访一次性引导卡(I1-2)。不做多步 tour —— 一张卡:按 onboarding persona
/// 预填 3 个 Machi AI 快捷问题 + 主 CTA「30 秒定级」。点 CTA/chip 视为已消费
/// (onConsumed 只写 UserDefaults 标记,卡片留到下次进首页再消失,避免推进
/// NavigationLink 时卡片被移除断导航);✕ 立即收起。游客可直接进定级,提交时
/// 由 GuideJLPTPlacementView 的 GuestGate 兜底。
private struct GuideIntroCard: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @AppStorage("onboardingPersona") private var onboardingPersona = ""
    let onDismiss: () -> Void
    let onConsumed: () -> Void

    /// persona(arrival_stage)→ 3 个示范问题:让新用户 5 秒内看到「和我有关」。
    private var personaQuestions: [String] {
        switch onboardingPersona {
        case "pre_arrival":
            return [
                guideText(language, "留学签证 COE 怎么办理？", "在留資格認定証明書（COE）の取り方は？", "How do I get a COE for my student visa?"),
                guideText(language, "来日本前要准备哪些材料？", "渡日前に何を準備すべき？", "What should I prepare before coming to Japan?"),
                guideText(language, "语言学校怎么选？", "語学学校の選び方は？", "How do I choose a language school?")
            ]
        case "just_arrived":
            return [
                guideText(language, "刚到日本要办哪些手续？", "来日直後の手続きは？", "What paperwork do I need right after arriving?"),
                guideText(language, "怎么开银行账户和办手机卡？", "銀行口座と携帯の契約方法は？", "How do I open a bank account and get a SIM?"),
                guideText(language, "在留卡地址变更怎么办？", "在留カードの住所変更は？", "How do I update the address on my residence card?")
            ]
        case "first_year":
            return [
                guideText(language, "资格外活动许可怎么申请？", "資格外活動許可の申請方法は？", "How do I apply for a part-time work permit?"),
                guideText(language, "JLPT 什么时候报名和考试？", "JLPT の申込と試験日は？", "When are JLPT registration and exam dates?"),
                guideText(language, "留学签证怎么续？", "留学ビザの更新方法は？", "How do I renew my student visa?")
            ]
        case "long_term":
            return [
                guideText(language, "日企面试怎么准备？", "日本企業の面接対策は？", "How do I prep for interviews at Japanese firms?"),
                guideText(language, "永住申请需要什么条件？", "永住申請の条件は？", "What are the requirements for permanent residency?"),
                guideText(language, "怎么换工作签证？", "就労ビザへの変更方法は？", "How do I switch to a work visa?")
            ]
        default:
            return [
                guideText(language, "留学签证怎么续？", "留学ビザの更新方法は？", "How do I renew my student visa?"),
                guideText(language, "JLPT 考什么、怎么备考？", "JLPT の内容と対策は？", "What's on the JLPT and how do I prep?"),
                guideText(language, "东京哪里租房便宜？", "東京で家賃が安いエリアは？", "Where is rent cheaper in Tokyo?")
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .top, spacing: KXSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(guideText(language, "第一次来？两步就上手", "はじめてですか？2ステップで開始", "New here? Start in two steps"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(KXColor.livingInk)
                    Text(guideText(language, "先测日语水平，或直接问 Machi AI。", "まずレベル判定、または Machi AI に質問。", "Check your Japanese level, or just ask Machi AI."))
                        .font(.footnote)
                        .foregroundStyle(KXColor.livingMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.livingMuted)
                        .frame(width: 28, height: 28)
                        .background(KXColor.livingSurface, in: Circle())
                }
                .buttonStyle(.fullArea)
                .contentShape(Circle())
                .accessibilityIdentifier("guide.intro.dismiss")
                .accessibilityLabel(guideText(language, "关闭", "閉じる", "Close"))
            }

            NavigationLink {
                GuideJLPTPlacementView()
            } label: {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.subheadline.weight(.bold))
                    Text(guideText(language, "30 秒测水平，拿到备考计划", "30秒でレベル判定して計画を作る", "Find your level in 30 seconds"))
                        .font(.subheadline.weight(.bold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(KXColor.onAccent)
                .padding(.vertical, 14)
                .padding(.horizontal, KXSpacing.lg)
                .background(KXColor.livingAccent, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .shadow(color: KXColor.livingAccent.opacity(0.24), radius: 10, y: 4)
            }
            .buttonStyle(KXPressableStyle(scale: 0.97))
            .simultaneousGesture(TapGesture().onEnded { onConsumed() })
            .accessibilityIdentifier("guide.intro.placement")

            FlowLayout(spacing: 7) {
                ForEach(personaQuestions, id: \.self) { question in
                    Button {
                        onConsumed()
                        router.open(.guideAI(prompt: question), in: .guide)
                    } label: {
                        Text(question)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(KXColor.livingAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(KXColor.livingAccentSoft, in: Capsule())
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Capsule())
                }
            }
        }
        .padding(KXSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous)
                .stroke(KXColor.livingAccent.opacity(0.22), lineWidth: 0.9)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
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
            HStack(spacing: KXSpacing.md) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .frame(width: 44, height: 44)
                    .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
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
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous).stroke(KXColor.separator.opacity(0.7), lineWidth: 0.8))
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
                HStack(spacing: KXSpacing.sm) {
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
                            .padding(.horizontal, KXSpacing.md)
                            .frame(height: 38)
                            .background(KXColor.cardBackground, in: Capsule())
                            .overlay(Capsule().stroke(KXColor.separator, lineWidth: 0.8))
                        }
                        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
                    }
                }
                .padding(.vertical, KXSpacing.xxs)
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
                .padding(.vertical, KXSpacing.xxs)
            }
        }
    }
}

/// The two permanent doors of the Guide tab: everything entitled by the
/// membership lives behind Member area, while templates and human help live behind
/// 资料与服务. Side-by-side tiles so the split is legible at a glance.
/// Guide 首页的商城板块:会员/商城双入口卡 + 最多 3 张精选商品卡
/// (付费优先、其次免费引流款)。自加载、拿不到数据时静默退化为纯入口卡。
private struct GuideStoreSection: View {
    @State private var products: [KaiXGuideProductDTO] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideDualEntrySection()
            if !products.isEmpty {
                VStack(spacing: 10) {
                    ForEach(products) { product in
                        GuideProductCard(product: product)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard products.isEmpty else { return }
        let resp = try? await KaiXAPIClient.shared.guideProducts(country: "jp", pageSize: 12)
        let items = (resp?.items ?? []).filter { !$0.isComingSoon && !$0.isService }
        // I1-1:is_featured + sort_order 置顶 hero SKU;非精选保持原「付费优先、
        // 免费引流其次」的次序兜底(后台没勾精选时板块不塌)。
        let featured = items
            .filter { $0.isFeatured == true }
            .sorted { ($0.sortOrder ?? Int.max) < ($1.sortOrder ?? Int.max) }
        let rest = items.filter { $0.isFeatured != true }
        let paid = rest.filter { !$0.isFree }
        let free = rest.filter { $0.isFree }
        products = Array((featured + paid + free).prefix(3))
        // C-2 客户端漏斗:首页商城板块实际渲染出商品才算一次曝光。
        if let hero = products.first {
            Task { await KaiXAPIClient.shared.funnelEvent("store_hero_view", entityType: "guide_store", entityId: hero.slug, props: ["placement": "guide_home"]) }
        }
    }
}

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
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
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
            .kxGlassSurface(radius: KXRadius.card)
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
                    .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
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
            .padding(KXSpacing.md)
            .kxGlassSurface(radius: KXRadius.hero)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }
}

struct GuideArticleCard: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let article: KaiXGuideArticleDTO
    var compact = false

    var body: some View {
        Button {
            router.open(.guideArticle(slug: article.slug))
        } label: {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
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
                            .padding(.vertical, KXSpacing.xs)
                            .background(KXColor.softBackground, in: Capsule())
                    }
                }
            }
            .padding(compact ? 14 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxGlassSurface(radius: KXRadius.card)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }
}

/// #1: member-price surface for Guide resources.
///
/// - No member price on the product → renders nothing (older payloads / free /
///   coming-soon items just show the normal price elsewhere).
/// - Member → strikethrough original price + the member price, framed as savings.
/// - Non-member → a tappable "会员价 ¥xx" chip that opens the membership page.
struct GuideMemberPriceRow: View {
    let product: KaiXGuideProductDTO
    let isMember: Bool
    let language: AppLanguage
    var onUpgrade: () -> Void = {}

    /// The member price label to show. Prefers the server-formatted
    /// `memberPriceLabel`; falls back to formatting `memberPrice`.
    private var memberLabel: String? {
        if let label = product.memberPriceLabel, !label.isEmpty { return label }
        if let mp = product.memberPrice, mp >= 0, product.isMemberDiscount == true || product.isMemberIncluded == true {
            return mp == 0 ? guideText(language, "免费", "無料", "Free")
                           : KaiXPriceFormatter.format(Double(mp), currency: product.currency)
        }
        return nil
    }

    /// The regular price, shown struck-through when a member price undercuts it.
    private var originalLabel: String {
        if !product.priceLabel.isEmpty { return product.priceLabel }
        let base = product.originalPrice ?? product.price
        return KaiXPriceFormatter.format(Double(base), currency: product.currency)
    }

    private var isMemberIncludedFree: Bool {
        product.isMemberIncluded == true && (product.memberPrice ?? -1) == 0
    }

    var body: some View {
        // Nothing to show for free / coming-soon / appointment items or when
        // there simply is no member price.
        if product.isFree || product.isComingSoon || product.isAppointmentOnly == true || product.isPriceHidden == true {
            EmptyView()
        } else if let memberLabel {
            if isMember {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(guideText(language, "会员价", "会員価格", "Member price"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(memberLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                    Text(originalLabel)
                        .font(.caption)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            } else {
                Button(action: onUpgrade) {
                    HStack(spacing: KXSpacing.sm) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        (Text(guideText(language, "会员价 ", "会員価格 ", "Member price "))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                         + Text(memberLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.accent))
                        Spacer(minLength: 0)
                        Text(isMemberIncludedFree
                             ? guideText(language, "开通会员免费看", "会員なら無料", "Free for members")
                             : guideText(language, "开通会员", "会員登録", "Get membership"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(KXColor.onAccent)
                            .padding(.horizontal, KXSpacing.sm)
                            .padding(.vertical, KXSpacing.xs)
                            .background(KXColor.accent, in: Capsule())
                    }
                    .padding(.horizontal, KXSpacing.md)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else {
            EmptyView()
        }
    }
}

struct GuideProductCard: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let product: KaiXGuideProductDTO

    /// Whether the browsing user is a member — read from the shared store so the
    /// card can show member savings inline.
    @EnvironmentObject private var userStore: UserStore
    private var isMember: Bool {
        guard let id = userStore.currentUserId, let user = userStore.usersById[id] else {
            return product.access?.memberUnlocked == true
        }
        return user.isVerifiedMember || product.access?.memberUnlocked == true
    }

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
                if let memberChip = memberPriceChip {
                    Spacer(minLength: 0)
                    memberChip
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
    }

    /// Compact member-price line on the card (informational — the whole card is a
    /// tap target to the detail page where the upsell/upgrade CTA lives). Nil when
    /// there is no member price or the item is free/coming-soon.
    @ViewBuilder
    private var memberPriceChip: (some View)? {
        let label: String? = {
            if let l = product.memberPriceLabel, !l.isEmpty { return l }
            if let mp = product.memberPrice, product.isMemberDiscount == true || product.isMemberIncluded == true {
                return mp == 0 ? guideText(language, "免费", "無料", "Free")
                               : KaiXPriceFormatter.format(Double(mp), currency: product.currency)
            }
            return nil
        }()
        if let label,
           !(product.isFree || product.isComingSoon || product.isAppointmentOnly == true || product.isPriceHidden == true) {
            HStack(spacing: KXSpacing.xs) {
                Image(systemName: "checkmark.seal.fill").kxScaledFont(9).foregroundStyle(.blue)
                Text(isMember
                     ? guideText(language, "会员价 \(label)", "会員価格 \(label)", "Member \(label)")
                     : guideText(language, "会员价 \(label)", "会員価格 \(label)", "Member price \(label)"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .lineLimit(1)
            }
            .padding(.horizontal, KXSpacing.sm)
            .padding(.vertical, KXSpacing.xs)
            .background(KXColor.accentSoft, in: Capsule())
        }
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
                        .padding(.horizontal, KXSpacing.sm)
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
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
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
                        .padding(.horizontal, KXSpacing.sm)
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
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
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
        .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
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
        .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
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
        .padding(.top, KXSpacing.xxs)
    }
}

struct GuideIconBubble: View {
    let icon: String
    let color: Color
    var size: CGFloat = 50

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.40, weight: .bold))
            .foregroundStyle(KXColor.onTint(color))
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
                .padding(.horizontal, KXSpacing.md)
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
            .padding(.horizontal, KXSpacing.sm)
            .padding(.vertical, KXSpacing.xs)
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
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
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

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Parse an ISO/date string and render it in a short, localized style. Returns
    /// nil for empty/unparseable input so callers can skip the row entirely.
    static func shortDate(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let date = KXDateParsing.parse(raw) else { return nil }
        return shortDateFormatter.string(from: date)
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
