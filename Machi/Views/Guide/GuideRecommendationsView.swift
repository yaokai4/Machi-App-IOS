import SwiftUI

/// Contextual Guide resources and services. Server-first over
/// `/api/guide/recommendations`; recommendations are tied to the user's
/// profile, plan, and todos instead of behaving like a standalone shop.
struct GuideRecommendationsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    var planType: String? = nil
    var todoType: String? = nil

    @State private var materials: [KaiXGuideProductDTO] = []
    @State private var services: [KaiXGuideProductDTO] = []
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: KXSpacing.lg) {
                    GuideOSHeaderRow(
                        title: guideOSText(language, "资料与服务推荐", "資料・サービスのおすすめ", "Recommended materials & services"),
                        subtitle: guideOSText(language, "根据你的提醒设置、计划和 Todo 推荐真正需要的资料与人工服务。", "リマインダー設定・計画・Todoに合わせて必要な資料とサービスを推薦します。", "Matched to your reminders, plan, and todos.")
                    )
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if failed && materials.isEmpty && services.isEmpty {
                        GuideOSEmptyMini(text: guideOSText(language, "推荐暂时无法加载，下拉重试。", "おすすめを読み込めませんでした。引っ張って再試行。", "Couldn't load recommendations. Pull to retry."))
                    } else {
                        section(title: guideOSText(language, "推荐资料", "おすすめ資料", "Materials"), items: materials)
                        section(title: guideOSText(language, "推荐服务", "おすすめサービス", "Services"), items: services)
                        if materials.isEmpty && services.isEmpty {
                            GuideOSEmptyMini(text: guideOSText(language, "暂时没有匹配的资料或服务。", "一致する資料・サービスはありません。", "No matching materials or services yet."))
                        }
                    }
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "资料与服务", "資料・サービス", "Materials & services"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private func section(title: String, items: [KaiXGuideProductDTO]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text(title).font(.subheadline.weight(.bold))
                ForEach(items) { item in
                    Button { router.open(.guideProduct(slug: item.slug)) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.isService ? "sparkles" : "doc.text.fill")
                                .kxScaledFont(13, weight: .bold)
                                .foregroundStyle(KXColor.onTint(item.isService ? Color.purple : KXColor.accent))
                                .frame(width: 30, height: 30)
                                .background(item.isService ? Color.purple : KXColor.accent, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                                let sub = item.subtitle.isEmpty ? (item.ctaLabel ?? item.priceLabel) : item.subtitle
                                if !sub.isEmpty {
                                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(KXSpacing.md)
                        .kxGlassSurface(radius: KXRadius.md)
                    }
                    .buttonStyle(.fullArea)
        .contentShape(Rectangle())
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        failed = false
        defer { isLoading = false }
        do {
            let resp = try await KaiXAPIClient.shared.guideRecommendations(planType: planType, todoType: todoType, language: currentGuideOSLanguage())
            materials = resp.materials
            services = resp.services
        } catch {
            failed = true
        }
    }
}

struct GuideOSRecommendationStrip: View {
    @Environment(\.appLanguage) private var language

    let products: [KaiXGuideProductDTO]
    let services: [KaiXGuideProductDTO]
    let onOpenProduct: (String) -> Void
    let onOpenServices: () -> Void

    private var items: [KaiXGuideProductDTO] {
        Array((products + services).prefix(5))
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(guideOSText(language, "相关资料与服务", "関連資料・サービス", "Related materials & services"))
                            .font(.subheadline.weight(.bold))
                        Text(guideOSText(language, "按你的 Todo 自动推荐资料和服务", "Todoに合わせて資料とサービスを推薦", "Recommended from your todos"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(action: onOpenServices) {
                        Text(guideOSText(language, "全部", "すべて", "All"))
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.fullArea)
        .contentShape(Rectangle())
                    .foregroundStyle(KXColor.accent)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            Button {
                                onOpenProduct(item.slug)
                            } label: {
                                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                                    HStack(spacing: 7) {
                                        Image(systemName: item.isService ? "sparkles" : "doc.text.fill")
                                            .kxScaledFont(13, weight: .bold)
                                            .foregroundStyle(KXColor.onTint(item.isService ? Color.purple : KXColor.accent))
                                            .frame(width: 28, height: 28)
                                            .background(item.isService ? Color.purple : KXColor.accent, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                                        Text(item.isService ? guideOSText(language, "服务", "サービス", "Service") : guideOSText(language, "资料", "資料", "Material"))
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                    }
                                    Text(item.title)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(item.subtitle.isEmpty ? (item.ctaLabel ?? item.priceLabel) : item.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(width: 176, alignment: .leading)
                                .padding(KXSpacing.md)
                                .background(KXColor.livingSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                                        .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.fullArea)
        .contentShape(Rectangle())
                        }
                    }
                    .padding(.trailing, KXSpacing.xxs)
                }
            }
        }
    }
}
