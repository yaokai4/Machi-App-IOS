import Combine
import SwiftUI
import UIKit

@MainActor
final class LocalNewsListViewModel: ObservableObject {
    @Published var posts: [KaiXEditorialPostDTO] = []
    @Published var related: [KaiXEditorialPostDTO] = []
    @Published var state: ScreenState = .idle
    @Published var selectedCategory = ""
    @Published var sort = "latest"

    func load(country: String? = nil, city: String? = nil, language: String? = nil, limit: Int = 30) async {
        state = posts.isEmpty ? .loading : state
        do {
            let response = try await KaiXAPIClient.shared.news(
                country: country,
                city: city,
                language: language,
                category: selectedCategory.isEmpty ? nil : selectedCategory,
                sort: sort,
                limit: limit
            )
            posts = response.items
            state = posts.isEmpty ? .empty : .loaded
        } catch {
            state = posts.isEmpty ? .error(error.kaixUserMessage) : .loaded
        }
    }
}

@MainActor
final class LocalNewsDetailViewModel: ObservableObject {
    @Published var post: KaiXEditorialPostDTO?
    @Published var related: [KaiXEditorialPostDTO] = []
    @Published var comments: [KaiXEditorialCommentDTO] = []
    @Published var state: ScreenState = .idle
    @Published var commentText = ""

    func load(id: String) async {
        state = .loading
        do {
            let response = try await KaiXAPIClient.shared.newsDetail(id)
            post = response.post
            related = response.related
            comments = (try? await KaiXAPIClient.shared.newsComments(id)) ?? []
            state = .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func toggleSave() async {
        guard let post else { return }
        do {
            self.post = try await KaiXAPIClient.shared.setNewsSaved(post.id, !post.saved)
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func sendComment() async {
        guard let post, !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            _ = try await KaiXAPIClient.shared.createNewsComment(post.id, content: commentText)
            commentText = ""
            comments = try await KaiXAPIClient.shared.newsComments(post.id)
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}

struct LocalNewsDeskStripView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = LocalNewsListViewModel()

    let country: String?
    let city: String?
    var title: String = "本地资讯台"
    var variant: Variant = .home

    enum Variant { case home, city }

    var body: some View {
        Group {
            if !viewModel.posts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(title, systemImage: "newspaper")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            router.open(.localNews(country: country ?? "", city: city ?? ""))
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KXColor.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    if let lead = viewModel.posts.first {
                        Button {
                            router.open(.localNewsDetail(newsId: lead.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(categoryLabel(lead.category))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(KXColor.accent)
                                Text(lead.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(lead.summary.isEmpty ? lead.body : lead.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text("\(lead.author_display_name) · \(relativeDate(lead.published_at ?? lead.created_at))")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(KXColor.softBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(viewModel.posts.dropFirst().prefix(variant == .city ? 3 : 2)) { post in
                        Button {
                            router.open(.localNewsDetail(newsId: post.id))
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: post.category == "traffic_alert" ? "tram.fill" : "newspaper")
                                    .font(.caption)
                                    .foregroundStyle(KXColor.accent)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(post.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(categoryLabel(post.category))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .kxGlassSurface(radius: KXRadius.lg)
            }
        }
        .task(id: "\(country ?? "").\(city ?? "").\(viewModel.selectedCategory).\(viewModel.sort)") {
            await viewModel.load(country: country, city: city, limit: variant == .city ? 5 : 4)
        }
    }
}

struct LocalNewsDeskListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = LocalNewsListViewModel()
    @State private var selectedCity: String = ""

    let country: String
    let city: String

    private let categories: [(String, String)] = [
        ("", "全部"),
        ("local_news", "城市快讯"),
        ("traffic_alert", "交通"),
        ("weather_alert", "天气"),
        ("earthquake_alert", "地震"),
        ("typhoon_alert", "台风"),
        ("policy_update", "政策"),
        ("immigration_visa", "在留"),
        ("city_event", "活动"),
        ("life_notice", "生活"),
        ("public_safety", "安全"),
        ("economy", "经济"),
        ("technology", "科技"),
        ("culture", "文化"),
        ("sports", "体育"),
        ("education", "教育"),
        ("health", "健康"),
        ("travel", "旅行"),
        ("editor_pick", "精选"),
    ]
    private let cityOptions: [(String, String)] = [("", "Japan-wide"), ("tokyo", "Tokyo"), ("osaka", "Osaka")]
    private var activeCity: String { selectedCity.isEmpty && !city.isEmpty ? city : selectedCity }

    var body: some View {
        VStack(spacing: 0) {
            header
            cityChips
            categoryChips
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    LoadingView()
                case .empty:
                    EmptyStateView(title: "暂无本地资讯", subtitle: "编辑部发布后会显示在这里。", systemImage: "newspaper")
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await viewModel.load(country: country.isEmpty ? "jp" : country, city: activeCity) }
                    }
                case .loaded:
                    list
                }
            }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(country).\(activeCity).\(viewModel.selectedCategory).\(viewModel.sort)") {
            await viewModel.load(country: country.isEmpty ? "jp" : country, city: activeCity)
        }
    }

    private var header: some View {
        HStack(spacing: KXSpacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("本地资讯")
                    .font(.headline.weight(.semibold))
                Text("看看这座城市最近发生了什么。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.sort = viewModel.sort == "latest" ? "popular" : "latest"
            } label: {
                Image(systemName: viewModel.sort == "latest" ? "clock" : "flame.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(KXColor.accent)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.md)
        .kxGlassBar(ignoresTopSafeArea: true)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.0) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            viewModel.selectedCategory = item.0
                        }
                    } label: {
                        Text(item.1)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .kxGlassCapsule(isSelected: viewModel.selectedCategory == item.0)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.selectedCategory == item.0 ? KXColor.accent : .primary)
                }
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.vertical, 8)
        }
    }

    private var cityChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cityOptions, id: \.0) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            selectedCity = item.0
                        }
                    } label: {
                        Text(item.1)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .kxGlassCapsule(isSelected: activeCity == item.0)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(activeCity == item.0 ? KXColor.accent : .primary)
                }
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.top, 8)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.posts) { post in
                    Button {
                        router.open(.localNewsDetail(newsId: post.id))
                    } label: {
                        LocalNewsRow(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.vertical, KXSpacing.sm)
        }
        .refreshable {
            await viewModel.load(country: country.isEmpty ? "jp" : country, city: activeCity)
        }
    }
}

struct LocalNewsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = LocalNewsDetailViewModel()

    let newsId: String
    let currentUser: UserEntity

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    LoadingView()
                case .empty:
                    EmptyStateView(title: "资讯不存在", subtitle: "可能已隐藏或删除。", systemImage: "newspaper")
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await viewModel.load(id: newsId) }
                    }
                case .loaded:
                    content
                }
            }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: newsId) {
            await viewModel.load(id: newsId)
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            Spacer()
            Text("本地资讯")
                .font(.headline.weight(.semibold))
            Spacer()
            Button { shareCurrentLink() } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.md)
        .kxGlassBar(ignoresTopSafeArea: true)
    }

    private var content: some View {
        ScrollView {
            if let post = viewModel.post {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(categoryLabel(post.category))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                        Text(post.title)
                            .font(.title2.weight(.black))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(post.author_display_name) · \(relativeDate(post.published_at ?? post.created_at))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if !post.summary.isEmpty {
                        Text(post.summary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .kxGlassSurface(radius: KXRadius.md)
                    }

                    Text(post.body)
                        .font(.body)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    sourceBlock(post)
                    if post.official_source_required == true || post.risk_level == "high" {
                        Text("此内容由 Machi 编辑部根据公开来源整理，具体信息请以官方发布为准。")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .kxGlassSurface(radius: KXRadius.md)
                    }
                    tagCloud(post.tags)
                    actionRow(post)
                    commentsBlock
                    relatedBlock
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.vertical, KXSpacing.md)
            }
        }
    }

    private func sourceBlock(_ post: KaiXEditorialPostDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("来源：\(post.source_name ?? "Machi Local Desk")")
                .font(.subheadline.weight(.bold))
            if let sourceDate = post.source_published_at, !sourceDate.isEmpty {
                Text("原文发布时间：\(relativeDate(sourceDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let urlString = post.original_url ?? post.source_url,
               let url = URL(string: urlString) {
                Button {
                    Task {
                        _ = try? await KaiXAPIClient.shared.trackNewsSourceClick(post.id)
                        await MainActor.run {
                            UIApplication.shared.open(url)
                        }
                    }
                } label: {
                    Label("查看原文", systemImage: "link")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .kxGlassSurface(radius: KXRadius.md)
    }

    private func tagCloud(_ tags: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(KXColor.softBackground, in: Capsule())
            }
        }
    }

    private func actionRow(_ post: KaiXEditorialPostDTO) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await viewModel.toggleSave() }
            } label: {
                Label(post.saved ? "已收藏 \(post.save_count)" : "收藏 \(post.save_count)", systemImage: post.saved ? "bookmark.fill" : "bookmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .kxGlassCapsule(isSelected: post.saved)
            }
            .buttonStyle(.plain)
            Button {
                shareCurrentLink()
            } label: {
                Label("分享 \(post.share_count ?? 0)", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .kxGlassCapsule(isSelected: false)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var commentsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("评论")
                .font(.headline.weight(.bold))
            HStack(spacing: 8) {
                TextField("写一条评论", text: $viewModel.commentText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .kxGlassSurface(radius: KXRadius.md)
                Button {
                    Task { await viewModel.sendComment() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(KXColor.accent, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(viewModel.comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.author?.display_name ?? "Machi 用户")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(comment.content)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .kxGlassSurface(radius: KXRadius.md)
            }
        }
    }

    private var relatedBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.related.isEmpty {
                Text("相关内容")
                    .font(.headline.weight(.bold))
                ForEach(viewModel.related) { post in
                    Button {
                        router.open(.localNewsDetail(newsId: post.id))
                    } label: {
                        LocalNewsRow(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shareCurrentLink() {
        guard let url = URL(string: "https://machicity.com/news/\(newsId)") else { return }
        UIPasteboard.general.string = url.absoluteString
        Task { _ = try? await KaiXAPIClient.shared.shareNews(newsId) }
    }
}

private struct LocalNewsRow: View {
    let post: KaiXEditorialPostDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(categoryLabel(post.category))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                Text(post.author_display_name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(relativeDate(post.published_at ?? post.created_at))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(post.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(post.summary.isEmpty ? post.body : post.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 10) {
                Label("\(post.save_count)", systemImage: "bookmark")
                Label("\(post.share_count ?? 0)", systemImage: "square.and.arrow.up")
                Label("\(post.comment_count)", systemImage: "bubble.right")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}

private func categoryLabel(_ category: String) -> String {
    switch category {
    case "traffic_alert": return "交通提醒"
    case "weather_alert": return "天气灾害"
    case "earthquake_alert": return "地震提醒"
    case "typhoon_alert": return "台风提醒"
    case "policy_update": return "政策更新"
    case "immigration_visa": return "在留签证"
    case "city_event": return "城市活动"
    case "life_notice": return "生活通知"
    case "housing_notice": return "租房搬家"
    case "housing_market": return "租房市场"
    case "work_study": return "工作留学"
    case "public_safety": return "公共安全"
    case "economy": return "经济"
    case "technology": return "科技"
    case "culture": return "文化"
    case "sports": return "体育"
    case "education": return "教育"
    case "health": return "健康"
    case "travel": return "旅行"
    case "editor_pick": return "编辑精选"
    case "weekly_digest": return "本周摘要"
    case "other": return "其他"
    default: return "城市快讯"
    }
}

private func relativeDate(_ iso: String) -> String {
    guard let date = parseNewsDate(iso) else { return iso }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func parseNewsDate(_ iso: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: iso) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso)
}
