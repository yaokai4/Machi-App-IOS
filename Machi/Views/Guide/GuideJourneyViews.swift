import Combine
import SwiftUI

// MARK: - Local-first progress store
//
// Step completion is stored locally (UserDefaults) so guests get a real sense
// of progress without logging in — the same local-first pattern the Discover
// favorites use. When the user is logged in, changes are best-effort synced to
// `/api/guide/progress` and server state is merged back in on load. Source of
// truth for a guest is the device; for a logged-in user the server reconciles.
@MainActor
final class GuideProgressStore: ObservableObject {
    static let shared = GuideProgressStore()

    @Published private(set) var statuses: [String: String] = [:]   // "journeyKey/stepKey" -> status
    private let defaultsKey = "guide_progress_v1"

    init() { load() }

    private func composite(_ journey: String, _ step: String) -> String { "\(journey)/\(step)" }

    func status(journey: String, step: String) -> String {
        statuses[composite(journey, step)] ?? "not_started"
    }

    func isDone(journey: String, step: String) -> Bool {
        status(journey: journey, step: step) == "done"
    }

    func doneCount(journey: String) -> Int {
        let prefix = "\(journey)/"
        return statuses.filter { $0.key.hasPrefix(prefix) && $0.value == "done" }.count
    }

    /// Apply a status locally and persist. Returns the previous value so the
    /// caller can roll back if a server sync fails.
    @discardableResult
    func setStatus(journey: String, step: String, _ status: String) -> String {
        let key = composite(journey, step)
        let previous = statuses[key] ?? "not_started"
        if status == "not_started" {
            statuses.removeValue(forKey: key)
        } else {
            statuses[key] = status
        }
        persist()
        return previous
    }

    /// Fold server progress into the local store in one write (load path).
    func merge(server entries: [String: KaiXGuideStepProgressState], journey: String) {
        for (stepKey, state) in entries where !stepKey.isEmpty {
            statuses[composite(journey, stepKey)] = state.status
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(statuses) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        statuses = decoded
    }
}

// MARK: - Shared helpers (file-scoped; GuideViews' equivalents are private)

private func journeyText(_ language: AppLanguage, _ zh: String, _ ja: String, _ en: String) -> String {
    KXListingCopy.pickText(language, zh, ja, en)
}

/// Self-contained hex -> Color (GuideViews' `Color(hex:)` is file-private).
private func guideHexColor(_ hex: String) -> Color {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return KXColor.accent }
    return Color(
        red: Double((rgb >> 16) & 0xFF) / 255.0,
        green: Double((rgb >> 8) & 0xFF) / 255.0,
        blue: Double(rgb & 0xFF) / 255.0
    )
}

/// Map a journey's editorial icon key to an SF Symbol.
func guideJourneySymbol(_ key: String) -> String {
    switch key {
    case "arrival": return "airplane.arrival"
    case "plan": return "list.bullet.clipboard.fill"
    case "home", "house": return "house.fill"
    case "plane": return "airplane"
    case "graduation": return "graduationcap.fill"
    case "briefcase": return "briefcase.fill"
    case "language": return "character.book.closed.fill"
    case "document": return "doc.text.fill"
    default: return "signpost.right.fill"
    }
}

/// Category -> journey key, for the "next step" hook in article detail.
func guideJourneyKey(forCategory categoryKey: String) -> String? {
    switch categoryKey {
    case "career_japan": return "job_hunting"
    case "study_japan": return "grad_school"
    case "study_abroad_japan": return "language_school"
    case "jlpt": return "jlpt"
    case "life_japan": return "arrival"
    default: return nil
    }
}

private func guideJourneyTitle(forKey key: String) -> String {
    GuideViewModelJourneyTitles.titles[key] ?? key
}

enum GuideViewModelJourneyTitles {
    static let titles: [String: String] = [
        "arrival": "刚到日本 7 天", "prepare": "准备来日本", "housing": "租房 / 搬家",
        "language_school": "语言学校 / 留学", "grad_school": "大学院 / 升学",
        "job_hunting": "日本就职", "jlpt": "JLPT / EJU 备考", "visa": "签证 / 手续",
    ]
}

// MARK: - Home: "你现在想解决什么" journey grid

struct GuideJourneyGrid: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var progress = GuideProgressStore.shared

    let journeys: [KaiXGuideJourneyDTO]

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        if !journeys.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(journeyText(language, "你现在想解决什么？", "いま何を解決したいですか？", "What do you need to get done?"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(journeyText(language, "选一个目标，Machi 把手续、资料、经验和服务整理成可执行步骤", "目標を選ぶと、手続き・資料・経験・サービスを実行可能なステップに整理します", "Pick a goal and Machi turns it into actionable steps"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(journeys) { journey in
                    GuideJourneyCard(
                        journey: journey,
                        doneCount: progress.doneCount(journey: journey.key)
                    ) {
                        router.open(.guideJourney(key: journey.key))
                    }
                }
            }
        }
    }
}

struct GuideJourneyCard: View {
    @Environment(\.appLanguage) private var language
    let journey: KaiXGuideJourneyDTO
    let doneCount: Int
    let action: () -> Void

    private var tint: Color { guideHexColor(journey.color) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: guideJourneySymbol(journey.icon))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .shadow(color: tint.opacity(0.35), radius: 8, y: 4)
                    Spacer()
                    if let total = journey.stepCount, total > 0 {
                        Text(doneCount > 0 ? "\(doneCount)/\(total)" : "\(total) 步")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(doneCount > 0 ? tint : .secondary)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(doneCount > 0 ? tint.opacity(0.14) : KXColor.softBackground, in: Capsule())
                    }
                }
                Text(journey.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(journey.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let total = journey.stepCount, total > 0, doneCount > 0 {
                    ProgressView(value: Double(min(doneCount, total)), total: Double(total))
                        .tint(tint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(13)
            .kxGlassSurface(radius: 20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Journey detail: timeline / checklist

@MainActor
final class GuideJourneyDetailViewModel: ObservableObject {
    @Published var detail: KaiXGuideJourneyDetailResponse?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var syncMessage: String?

    func load(journeyKey: String, country: String, language: String) async {
        guard country == "jp" else { detail = nil; isLoading = false; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await KaiXAPIClient.shared.guideJourney(journeyKey, country: country, language: language)
            detail = response
            if let serverProgress = response.progress, !serverProgress.isEmpty {
                GuideProgressStore.shared.merge(server: serverProgress, journey: journeyKey)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Optimistic local toggle; logged-in users sync to the server and roll the
    /// local change back if the sync fails. Guests stay purely local.
    func toggle(step: KaiXGuideJourneyStepDTO, journeyKey: String) async {
        let store = GuideProgressStore.shared
        let newStatus = store.isDone(journey: journeyKey, step: step.stepKey) ? "not_started" : "done"
        let previous = store.setStatus(journey: journeyKey, step: step.stepKey, newStatus)
        guard KaiXBackend.token != nil else { return }
        do {
            _ = try await KaiXAPIClient.shared.updateGuideProgress(journeyKey: journeyKey, stepKey: step.stepKey, status: newStatus)
        } catch {
            store.setStatus(journey: journeyKey, step: step.stepKey, previous)
            syncMessage = "进度未能同步到云端，已恢复本机状态，请稍后再试。"
        }
    }
}

struct GuideJourneyDetailView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var regionStore = RegionStore.shared
    @ObservedObject private var progress = GuideProgressStore.shared
    @StateObject private var model = GuideJourneyDetailViewModel()

    let journeyKey: String

    private var country: String { (regionStore.current?.countryCode ?? "jp").lowercased() }
    private var languageCode: String {
        switch language {
        case .ja: return "ja"
        case .en: return "en"
        case .zh, .system: return "zh-CN"
        }
    }

    var body: some View {
        ZStack {
            GuideBackground()
            content
        }
        .navigationTitle(journeyText(language, "行动路径", "アクションパス", "Action path"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(country):\(journeyKey)") {
            await model.load(journeyKey: journeyKey, country: country, language: languageCode)
        }
    }

    @ViewBuilder
    private var content: some View {
        if country != "jp" {
            GuideComingSoonView()
        } else if model.isLoading && model.detail == nil {
            LoadingView()
        } else if let message = model.errorMessage, model.detail == nil {
            ErrorStateView(message: message) {
                Task { await model.load(journeyKey: journeyKey, country: country, language: languageCode) }
            }
        } else if let detail = model.detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(detail.journey, steps: detail.steps)
                    if let sync = model.syncMessage, !sync.isEmpty {
                        Text(sync)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(Array(detail.steps.enumerated()), id: \.element.id) { index, step in
                        GuideJourneyStepRow(
                            step: step,
                            index: index + 1,
                            total: detail.steps.count,
                            isDone: progress.isDone(journey: journeyKey, step: step.stepKey),
                            tint: guideHexColor(detail.journey.color),
                            language: language,
                            onToggle: { Task { await model.toggle(step: step, journeyKey: journeyKey) } },
                            onOpenArticle: { router.open(.guideArticle(slug: $0)) },
                            onOpenProduct: { router.open(.guideProduct(slug: $0)) },
                            onOpenJourney: { router.open(.guideJourney(key: $0)) }
                        )
                    }
                    if let disclaimer = detail.disclaimer, !disclaimer.isEmpty {
                        Text(disclaimer)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(KXSpacing.screen)
                .padding(.bottom, 36)
            }
        } else {
            EmptyStateView(
                title: journeyText(language, "路径暂不可用", "パスは利用できません", "Path unavailable"),
                subtitle: journeyText(language, "联网后下拉刷新即可查看完整步骤。", "オンラインで再読み込みするとステップが表示されます。", "Reconnect and pull to refresh to see the steps."),
                systemImage: "signpost.right"
            )
        }
    }

    private func header(_ journey: KaiXGuideJourneyDTO, steps: [KaiXGuideJourneyStepDTO]) -> some View {
        let total = steps.count
        let done = min(progress.doneCount(journey: journeyKey), total)
        let tint = guideHexColor(journey.color)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: guideJourneySymbol(journey.icon))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .shadow(color: tint.opacity(0.38), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(journey.heroTitle.isEmpty ? journey.title : journey.heroTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    if journey.estimatedDays > 0 {
                        Text(journeyText(language, "预计 \(journey.estimatedDays) 天", "目安 \(journey.estimatedDays) 日", "~\(journey.estimatedDays) days"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !journey.heroSubtitle.isEmpty {
                Text(journey.heroSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(journeyText(language, "已完成 \(done)/\(total)", "完了 \(done)/\(total)", "Done \(done)/\(total)"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                        Spacer()
                        Text("\(total > 0 ? Int(round(Double(done) * 100 / Double(total))) : 0)%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                        .tint(tint)
                }
            }
        }
        .padding(18)
        .kxGlassSurface(radius: 24)
    }
}

private struct GuideJourneyStepRow: View {
    let step: KaiXGuideJourneyStepDTO
    let index: Int
    var total: Int = 0
    let isDone: Bool
    var tint: Color = KXColor.accent
    let language: AppLanguage
    let onToggle: () -> Void
    let onOpenArticle: (String) -> Void
    let onOpenProduct: (String) -> Void
    let onOpenJourney: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { onToggle() }
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isDone ? tint : Color.secondary.opacity(0.5))
                        .scaleEffect(isDone ? 1.08 : 1)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: isDone)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(journeyText(language, "第 \(index) 步", "ステップ \(index)", "Step \(index)"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint)
                        if !step.required {
                            GuideJourneyTag(text: journeyText(language, "可选", "任意", "Optional"))
                        }
                        if step.estimatedMinutes > 0 {
                            GuideJourneyTag(text: journeyText(language, "约 \(step.estimatedMinutes) 分钟", "約 \(step.estimatedMinutes) 分", "~\(step.estimatedMinutes) min"))
                        }
                        if !step.deadlineHint.isEmpty {
                            GuideJourneyTag(text: step.deadlineHint, tint: .orange)
                        }
                    }
                    Text(step.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                    if !step.summary.isEmpty {
                        Text(step.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let articles = step.relatedArticles, !articles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(articles.prefix(3)) { article in
                        Button { onOpenArticle(article.slug) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "doc.text")
                                    .font(.caption)
                                    .foregroundStyle(KXColor.accent)
                                Text(article.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let products = step.relatedProducts, !products.isEmpty {
                ForEach(products.prefix(2)) { product in
                    Button { onOpenProduct(product.slug) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "bag")
                                .font(.caption)
                                .foregroundStyle(KXColor.accent)
                            Text(product.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
            }

            if step.actionType == "journey", !step.actionTarget.isEmpty {
                Button { onOpenJourney(step.actionTarget) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right").font(.caption.weight(.bold))
                        Text(journeyText(language, "查看「\(guideJourneyTitle(forKey: step.actionTarget))」路径", "「\(guideJourneyTitle(forKey: step.actionTarget))」パスを見る", "Open the \(guideJourneyTitle(forKey: step.actionTarget)) path"))
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(KXColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(isDone ? 0.06 : 0))
                .allowsHitTesting(false)
        )
        .overlay(alignment: .leading) {
            // slim left accent bar that fills in once the step is done
            RoundedRectangle(cornerRadius: 2)
                .fill(isDone ? tint : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 14)
        }
    }
}

private struct GuideJourneyTag: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - "下一步" card for article detail

struct GuideJourneyNextStepCard: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    let categoryKey: String

    var body: some View {
        if let key = guideJourneyKey(forCategory: categoryKey) {
            Button { router.open(.guideJourney(key: key)) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "signpost.right.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(journeyText(language, "下一步", "次のステップ", "Next step"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(journeyText(language, "继续「\(guideJourneyTitle(forKey: key))」完整路径", "「\(guideJourneyTitle(forKey: key))」の全ステップへ", "Continue the \(guideJourneyTitle(forKey: key)) path"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                }
                .padding(15)
                .kxGlassSurface(radius: 20)
            }
            .buttonStyle(.plain)
        }
    }
}
