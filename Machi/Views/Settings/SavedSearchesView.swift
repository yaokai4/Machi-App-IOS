import SwiftUI

/// 订阅的搜索(saved searches)管理页:列出当前账号的全部订阅,左滑删除。
/// 订阅来自频道/搜索页的「保存此搜索」;有新匹配的发布上架时服务端推送通知。
/// Reached from 设置 → 通知设置旁的入口,or via KXRoute.savedSearches.
struct SavedSearchesView: View {
    @Environment(\.appLanguage) private var language
    @State private var items: [KaiXSavedSearchDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { Task { await load() } }
            } else if items.isEmpty {
                EmptyStateView(
                    title: L("savedSearchesEmpty", language),
                    subtitle: L("savedSearchesEmptyHelp", language),
                    systemImage: "bell.badge"
                )
            } else {
                searchList
            }
        }
        .kxPageBackground()
        .navigationTitle(L("savedSearchesTitle", language))
        .task { await load() }
    }

    private var searchList: some View {
        List {
            ForEach(items) { item in
                row(item)
                    .listRowBackground(KXColor.cardBackground)
            }
            .onDelete { indexSet in
                delete(at: indexSet)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: KaiXSavedSearchDTO) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            Text(displayTitle(item))
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(cadenceText(item.cadence))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .padding(.horizontal, KXSpacing.sm)
                    .frame(height: 20)
                    .background(KXColor.accent.opacity(0.12), in: Capsule())
                if let detail = detailText(item) {
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let count = item.matchCount, count > 0 {
                    Text("\(count) \(L("savedSearchMatchCount", language))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, KXSpacing.xs)
    }

    /// 首选服务端 label(创建时自动拼好),兜底关键词→垂类名。
    private func displayTitle(_ item: KaiXSavedSearchDTO) -> String {
        if let label = item.label, !label.isEmpty { return label }
        if let keyword = item.keyword, !keyword.isEmpty { return keyword }
        if let vertical = item.vertical, !vertical.isEmpty {
            return KXListingCopy.title(for: vertical, language)
        }
        return L("savedSearchesTitle", language)
    }

    /// 副行:垂类 · 类目 · 城市(有哪个拼哪个,与 label 重复也无妨)。
    private func detailText(_ item: KaiXSavedSearchDTO) -> String? {
        var bits: [String] = []
        if let vertical = item.vertical, !vertical.isEmpty {
            bits.append(KXListingCopy.title(for: vertical, language))
        }
        if let category = item.category, !category.isEmpty {
            bits.append(ListingFilterLocalizer.text(category, language))
        }
        if let citySlug = item.citySlug, !citySlug.isEmpty {
            bits.append(citySlug)
        }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    private func cadenceText(_ cadence: String?) -> String {
        switch cadence {
        case "daily": L("savedSearchCadenceDaily", language)
        case "off": L("savedSearchCadenceOff", language)
        default: L("savedSearchCadenceInstant", language)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await KaiXAPIClient.shared.savedSearches()
            isLoading = false
        } catch {
            errorMessage = error.kaixUserMessage
            isLoading = false
        }
    }

    /// 乐观删除:先移出列表,服务端失败再整表重载恢复。
    private func delete(at indexSet: IndexSet) {
        let removed = indexSet.map { items[$0] }
        items.remove(atOffsets: indexSet)
        Task {
            for item in removed {
                do {
                    try await KaiXAPIClient.shared.deleteSavedSearch(item.id)
                } catch {
                    await load()
                    return
                }
            }
        }
    }
}
