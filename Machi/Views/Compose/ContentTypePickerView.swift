import SwiftUI

/// Sheet shown before the composer opens. The picker is also exposed
/// inside the composer header so the user can switch types mid-edit
/// (their already-typed body / media survive the swap because they're
/// shared with the typed-form views via the same ComposeViewModel).
///
/// Layout:
/// 1. Search field — filter the grid by title / subtitle.
/// 2. Recent — UserDefaults-backed list of the last 4 types the user
///    picked. Hidden on first launch.
/// 3. Common — the 12 most-used types (first row of pickerOrder).
/// 4. More — the remaining types collapsed under a single toggle so
///    the page doesn't feel like a wall of icons.
struct ContentTypePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @AppStorage("compose.recentTypes") private var recentTypesRaw = ""
    @State private var query = ""
    @State private var showMore = false

    var current: ContentType?
    var onSelect: (ContentType) -> Void

    private static let commonCount = 9

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: KXSpacing.md),
        count: 4
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    headerHint
                    searchField

                    if !filteredResults.isEmpty {
                        // Search hit overrides the rest of the page so
                        // results are immediately scannable. We still
                        // expose the "recent" / "common" framing once
                        // the query clears.
                        section(title: nil, types: filteredResults)
                    } else if !query.isEmpty {
                        Text(L("ct_picker_noResult", language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, KXSpacing.lg)
                    } else {
                        if !recentTypes.isEmpty {
                            section(title: L("ct_picker_recent", language), types: recentTypes)
                        }
                        section(title: L("ct_picker_common", language), types: commonTypes)

                        if !extendedTypes.isEmpty {
                            DisclosureGroup(isExpanded: $showMore) {
                                section(title: nil, types: extendedTypes)
                                    .padding(.top, KXSpacing.sm)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(KXColor.accent)
                                    Text(L("ct_picker_more", language))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .padding(.horizontal, KaiXTheme.horizontalPadding)
                            .tint(KXColor.accent)
                        }
                    }
                }
                .padding(.vertical, KXSpacing.md)
            }
            .kxPageBackground()
            .navigationTitle(L("ct_picker_title", language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel", language)) { dismiss() }
                }
            }
        }
    }

    private var headerHint: some View {
        Text(L("ct_picker_sub", language))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, KaiXTheme.horizontalPadding)
    }

    private var searchField: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(L("ct_picker_search", language), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KXListingCopy.pickText(language, "清除", "クリア", "Clear"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .padding(.horizontal, KaiXTheme.horizontalPadding)
    }

    private func section(title: String?, types: [ContentType]) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
            }
            LazyVGrid(columns: columns, spacing: KXSpacing.md) {
                ForEach(types, id: \.self) { type in
                    cell(for: type)
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
        }
    }

    // MARK: - Sources

    private var commonTypes: [ContentType] {
        Array(ContentTypeRegistry.pickerOrder.prefix(Self.commonCount))
    }

    private var extendedTypes: [ContentType] {
        Array(ContentTypeRegistry.pickerOrder.dropFirst(Self.commonCount))
    }

    /// Recently-picked types, deduped against current. Stored as a
    /// pipe-delimited list so we don't pull SwiftData into this leaf
    /// view. Filtered to the live pickerOrder so a type that has been
    /// retired from the picker can't resurrect itself from history.
    private var recentTypes: [ContentType] {
        recentTypesRaw.split(separator: "|").compactMap { ContentType(rawValue: String($0)) }
            .filter { ContentTypeRegistry.pickerOrder.contains($0) }
            .prefix(4)
            .map { $0 }
    }

    /// Search match — checks localized title + subtitle against the
    /// trimmed query, case-insensitive.
    private var filteredResults: [ContentType] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()
        return ContentTypeRegistry.pickerOrder.filter { type in
            let title = L(type.spec.titleKey, language).lowercased()
            let sub = L(type.spec.subtitleKey, language).lowercased()
            return title.contains(needle) || sub.contains(needle)
        }
    }

    private func cell(for type: ContentType) -> some View {
        let spec = type.spec
        let isCurrent = current == type
        return Button {
            recordRecent(type)
            onSelect(type)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(spec.tint.opacity(isCurrent ? 0.20 : 0.12))
                    Image(systemName: spec.icon)
                        .kxScaledFont(20, weight: .semibold)
                        .foregroundStyle(spec.tint)
                }
                .frame(width: 48, height: 48)

                Text(L(spec.titleKey, language))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(L(spec.subtitleKey, language))
                    .kxScaledFont(10, relativeTo: .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, KXSpacing.xs)
            .background {
                RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                    .fill(isCurrent ? spec.tint.opacity(0.08) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                    .stroke(isCurrent ? spec.tint.opacity(0.5) : KXColor.glassStroke, lineWidth: isCurrent ? 1.0 : 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func recordRecent(_ type: ContentType) {
        var list = recentTypesRaw.split(separator: "|").map(String.init)
        list.removeAll { $0 == type.rawValue }
        list.insert(type.rawValue, at: 0)
        if list.count > 6 { list = Array(list.prefix(6)) }
        recentTypesRaw = list.joined(separator: "|")
    }
}
