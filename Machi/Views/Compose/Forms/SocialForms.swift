import SwiftUI

struct MeetupFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_meetup", icon: "hand.wave") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedTextField("fld_meetup_type", text: viewModel.stringBinding(PostAttributeKeys.meetupType))
            TypedDateTimeField(titleKey: "fld_meetup_time", viewModel: viewModel, attributeKey: PostAttributeKeys.meetupTime)
            TypedTextField("fld_location", text: viewModel.stringBinding(PostAttributeKeys.location))
            QuickLocationChips(viewModel: viewModel, attributeKey: PostAttributeKeys.location)
            TypedTextField("fld_people_limit", text: viewModel.intBinding(PostAttributeKeys.peopleLimit), keyboard: .numberPad)
            TypedTextField("fld_budget", text: viewModel.stringBinding(PostAttributeKeys.budget))
            TypedTextField("fld_description", text: viewModel.stringBinding(PostAttributeKeys.description), axis: .vertical)
            TypedTextField("safetyNotice", text: viewModel.stringBinding(PostAttributeKeys.safetyNotice), axis: .vertical)
        }
    }
}

struct DiningFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_dining", icon: "fork.knife") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title))
            TypedTextField("fld_restaurant_or_area", text: viewModel.stringBinding(PostAttributeKeys.restaurantOrArea), isRequired: true)
            QuickLocationChips(viewModel: viewModel, attributeKey: PostAttributeKeys.restaurantOrArea)
            TypedDateTimeField(titleKey: "fld_meetup_time", viewModel: viewModel, attributeKey: PostAttributeKeys.meetupTime)
            TypedTextField("fld_people_limit", text: viewModel.intBinding(PostAttributeKeys.peopleLimit), keyboard: .numberPad)
            TypedTextField("fld_budget", text: viewModel.stringBinding(PostAttributeKeys.budget))
            TypedTextField("fld_description", text: viewModel.stringBinding(PostAttributeKeys.description), axis: .vertical)
        }
    }
}

struct EventFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_event", icon: "calendar") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedDateTimeField(titleKey: "fld_event_time", viewModel: viewModel, attributeKey: PostAttributeKeys.eventTime)
            TypedTextField("fld_location", text: viewModel.stringBinding(PostAttributeKeys.location))
            QuickLocationChips(viewModel: viewModel, attributeKey: PostAttributeKeys.location)
            TypedTextField("fld_fee", text: viewModel.stringBinding(PostAttributeKeys.fee))
            TypedTextField("fld_capacity", text: viewModel.intBinding(PostAttributeKeys.capacity), keyboard: .numberPad)
            TypedTextField("fld_registration", text: viewModel.stringBinding(PostAttributeKeys.registrationMethod))
            TypedTextField("fld_description", text: viewModel.stringBinding(PostAttributeKeys.description), axis: .vertical)
        }
    }
}

// MARK: - Structured date-time field

/// Shared ISO8601 helpers for the structured time attributes
/// (fld_meetup_time / fld_event_time). The composer WRITES ISO8601
/// ("2026-07-25T10:00:00Z"); readers must stay backward compatible with the
/// free text users typed before this field existed ("周五晚上7点"), so
/// `parse` returning nil means "legacy text — show it as-is".
enum KXStructuredTime {
    private static let writer = ISO8601DateFormatter()
    private static let fractionalParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func encode(_ date: Date) -> String {
        writer.string(from: date)
    }

    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return writer.date(from: trimmed) ?? fractionalParser.date(from: trimmed)
    }

    /// Localized display for an ISO value; nil when `raw` is legacy free text
    /// (caller falls back to showing the raw string unchanged).
    static func display(_ raw: String, language: AppLanguage) -> String? {
        guard let date = parse(raw) else { return nil }
        let locale: Locale
        switch language {
        case .ja: locale = Locale(identifier: "ja_JP")
        case .en: locale = Locale(identifier: "en_US")
        case .zh: locale = Locale(identifier: "zh_CN")
        case .system: locale = Locale.current
        }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
        )
    }
}

/// Structured time input backed by a string attribute. Stores ISO8601 so the
/// detail page can localize / expire / calendar it, replacing the old
/// free-text field where everyone wrote a different format. Legacy free text
/// (from drafts saved before this change) is shown as-is with a one-tap
/// switch to the picker.
struct TypedDateTimeField: View {
    @Environment(\.appLanguage) private var language
    let titleKey: String
    @ObservedObject var viewModel: ComposePostViewModel
    let attributeKey: String
    var isRequired: Bool = false

    private var rawValue: String {
        viewModel.attributes[attributeKey]?.stringValue ?? ""
    }
    private var parsedDate: Date? {
        KXStructuredTime.parse(rawValue)
    }
    /// Old free-text value that predates the picker — kept readable, never
    /// silently destroyed.
    private var legacyText: String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && parsedDate == nil ? trimmed : nil
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { parsedDate ?? Self.defaultSeedDate() },
            set: { viewModel.setStringAttribute(attributeKey, KXStructuredTime.encode($0)) }
        )
    }

    /// The next full hour — a saner picker starting point than "right now".
    private static func defaultSeedDate() -> Date {
        Calendar.current.dateInterval(of: .hour, for: .now)?.end ?? .now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(L(titleKey, language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if isRequired {
                    Text("*")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
            }

            if let legacyText {
                HStack(spacing: KXSpacing.sm) {
                    Text(legacyText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Button {
                        viewModel.setStringAttribute(attributeKey, KXStructuredTime.encode(Self.defaultSeedDate()))
                    } label: {
                        Text(KXListingCopy.pickText(language, "改用选择器", "ピッカーで選ぶ", "Use picker"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                    }
                    .buttonStyle(.plain)
                    clearButton
                }
                .padding(.horizontal, KXSpacing.md)
                .frame(minHeight: 40)
                .kxGlassSurface(radius: KXRadius.md)
            } else if parsedDate != nil {
                HStack(spacing: KXSpacing.sm) {
                    DatePicker(
                        L(titleKey, language),
                        selection: dateBinding,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    Spacer(minLength: 0)
                    clearButton
                }
                .padding(.horizontal, KXSpacing.md)
                .frame(minHeight: 44)
                .kxGlassSurface(radius: KXRadius.md)
            } else {
                Button {
                    viewModel.setStringAttribute(attributeKey, KXStructuredTime.encode(Self.defaultSeedDate()))
                } label: {
                    HStack(spacing: KXSpacing.sm) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KXColor.accent)
                        Text(KXListingCopy.pickText(language, "选择日期与时间", "日時を選ぶ", "Pick date & time"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, KXSpacing.md)
                    .frame(minHeight: 40)
                    .kxGlassSurface(radius: KXRadius.md)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var clearButton: some View {
        Button {
            viewModel.setStringAttribute(attributeKey, "")
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KXListingCopy.pickText(language, "清除时间", "日時をクリア", "Clear time"))
    }
}

// MARK: - Quick location chips

/// 常用地点快捷 chips:约局/聚餐/活动高频集中在这些商圈,点一下直接填入
/// 地点字段(再点取消),不用每次手打;手输任意地点仍然可用。
struct QuickLocationChips: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var viewModel: ComposePostViewModel
    let attributeKey: String

    private struct Spot: Identifiable {
        let zh: String
        let ja: String
        let en: String
        var id: String { ja }
    }

    private static let spots: [Spot] = [
        Spot(zh: "新宿", ja: "新宿", en: "Shinjuku"),
        Spot(zh: "涩谷", ja: "渋谷", en: "Shibuya"),
        Spot(zh: "池袋", ja: "池袋", en: "Ikebukuro"),
        Spot(zh: "上野", ja: "上野", en: "Ueno"),
        Spot(zh: "银座", ja: "銀座", en: "Ginza"),
        Spot(zh: "秋叶原", ja: "秋葉原", en: "Akihabara"),
        Spot(zh: "新大久保", ja: "新大久保", en: "Shin-Okubo"),
        Spot(zh: "横滨", ja: "横浜", en: "Yokohama")
    ]

    var body: some View {
        FlowLayout(spacing: KXSpacing.xs) {
            ForEach(Self.spots) { spot in
                let label = KXListingCopy.pickText(language, spot.zh, spot.ja, spot.en)
                let isSelected = viewModel.attributes[attributeKey]?.stringValue == label
                Button {
                    viewModel.setStringAttribute(attributeKey, isSelected ? "" : label)
                } label: {
                    Text(label)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .kxGlassCapsule(isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? KXColor.accent : .primary)
            }
        }
    }
}
