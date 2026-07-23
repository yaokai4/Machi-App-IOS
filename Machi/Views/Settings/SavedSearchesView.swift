import SwiftUI

/// 订阅的搜索(saved searches)管理页:列出当前账号的全部订阅,左滑删除,
/// 点行回放——router 回到对应频道并携带订阅时的条件(关键词/类目/attr/价格)。
/// 订阅来自频道/搜索页的「保存此搜索」;有新匹配的发布上架时服务端推送通知。
/// Reached from 设置 → 通知设置旁的入口,or via KXRoute.savedSearches.
struct SavedSearchesView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @State private var items: [KaiXSavedSearchItemDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// 串行删除链:连续左滑会各自起 Task 并发删除;旧实现里前一个删除失败触发的
    /// 整表 load() 会把仍在途的后一个删除"复活"回列表(回载与在途删除竞态),之后
    /// 那条在服务端删成功了本地却不再更新。所有删除排到同一条链上串行执行。
    @State private var deleteChain: Task<Void, Never>?

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

    private func row(_ item: KaiXSavedSearchItemDTO) -> some View {
        Button {
            replay(item)
        } label: {
            HStack(spacing: KXSpacing.sm) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    Text(displayTitle(item))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
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
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, KXSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("savedSearch.row")
    }

    /// 首选服务端 label(创建时自动拼好),兜底关键词→垂类名。
    private func displayTitle(_ item: KaiXSavedSearchItemDTO) -> String {
        if let label = item.label, !label.isEmpty { return label }
        if let keyword = item.keyword, !keyword.isEmpty { return keyword }
        if let vertical = item.vertical, !vertical.isEmpty {
            return KXListingCopy.title(for: vertical, language)
        }
        return L("savedSearchesTitle", language)
    }

    /// 副行:垂类 · 类目 · 城市(有哪个拼哪个,与 label 重复也无妨)。
    private func detailText(_ item: KaiXSavedSearchItemDTO) -> String? {
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

    // MARK: - replay

    /// 点行回放:还原订阅时的条件并跳回对应频道。无垂类(纯关键词订阅)
    /// 走全局搜索页。
    private func replay(_ item: KaiXSavedSearchItemDTO) {
        let vertical = (item.vertical ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !vertical.isEmpty else {
            router.open(.search(initialQuery: item.keyword))
            return
        }
        var seed = ListingChannelSeed()
        if let keyword = item.keyword, !keyword.isEmpty { seed.query = keyword }
        if let category = item.category, !category.isEmpty { seed.category = category }
        if let filters = item.filters {
            for (key, value) in filters {
                guard let str = wireString(value), !str.isEmpty else { continue }
                switch key {
                case "min_price": seed.minPrice = str
                case "max_price": seed.maxPrice = str
                default:
                    if key.hasPrefix("attr_") { seed.attrs[String(key.dropFirst(5))] = str }
                }
            }
        }
        router.open(.cityListingsFiltered(regionCode: replayRegionCode(item), type: replayListingType(vertical), seed: seed))
    }

    /// vertical → 频道 listingType。hiring 归并到工作频道;for_sale/stays 由
    /// 频道内的 baseType/activeRentalTab 映射到住房频道对应分区。
    private func replayListingType(_ vertical: String) -> String {
        switch vertical {
        case "hiring", "job": return "work"
        default: return vertical
        }
    }

    /// 订阅的 region_code 可直接回放;只有 city_slug 时反查城市表;都没有
    /// (全国订阅)用默认城市——频道默认 scope 是「全国」,城市只影响标题。
    private func replayRegionCode(_ item: KaiXSavedSearchItemDTO) -> String {
        if let code = item.regionCode, KaiXRegionDirectory.resolve(regionCode: code) != nil {
            return code
        }
        if let slug = item.citySlug?.lowercased(), !slug.isEmpty {
            for country in KaiXRegionDirectory.countries {
                if country.hasProvinces {
                    for province in KaiXRegionDirectory.provinces(for: country.code)
                    where KaiXRegionDirectory.cities(country: country.code, province: province.code).contains(where: { $0.code == slug }) {
                        return KaiXRegionDirectory.composeRegionCode(country: country.code, province: province.code, city: slug)
                    }
                } else if KaiXRegionDirectory.cities(country: country.code, province: nil).contains(where: { $0.code == slug }) {
                    return KaiXRegionDirectory.composeRegionCode(country: country.code, province: nil, city: slug)
                }
            }
        }
        return "jp.tokyo.tokyo"
    }

    /// filter_json 值还原成查询参数字符串(旧数据/Web 端可能存了数字或布尔)。
    private func wireString(_ value: KaiXAttributeValue) -> String? {
        switch value.kind {
        case .string(let s): return s
        case .double(let d): return d.rounded() == d ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "true" : "false"
        case .json, .null: return nil
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

    /// 乐观删除:先移出列表;失败只把失败项插回原位,绝不整表 load()(整表回载
    /// 会与其他在途删除竞态,见 deleteChain 注释)。
    private func delete(at indexSet: IndexSet) {
        let removed = indexSet.map { (index: $0, item: items[$0]) }
        items.remove(atOffsets: indexSet)
        let previous = deleteChain
        deleteChain = Task {
            // 排在上一批删除之后串行执行,保证任意时刻至多一个删除在途。
            await previous?.value
            for entry in removed {
                do {
                    try await KaiXAPIClient.shared.deleteSavedSearch(entry.item.id)
                } catch {
                    // 恢复该项(行重新出现即失败信号,与旧行为一致)。
                    if !items.contains(where: { $0.id == entry.item.id }) {
                        items.insert(entry.item, at: min(entry.index, items.count))
                    }
                }
            }
        }
    }
}
