import Foundation

enum DateFormatterUtils {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relativeText(from date: Date, to referenceDate: Date = .now) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func relativeText(from date: Date, to referenceDate: Date = .now, language: AppLanguage) -> String {
        let seconds = max(0, Int(referenceDate.timeIntervalSince(date)))
        if seconds < 45 {
            switch language {
            case .ja: return "たった今"
            case .en: return "Just now"
            case .system, .zh: return "刚刚"
            }
        }

        let minutes = seconds / 60
        if minutes < 60 {
            switch language {
            case .ja: return "\(minutes)分前"
            case .en: return "\(minutes) min ago"
            case .system, .zh: return "\(minutes)分钟前"
            }
        }

        let hours = minutes / 60
        if hours < 24 {
            switch language {
            case .ja: return "\(hours)時間前"
            case .en: return "\(hours) hr ago"
            case .system, .zh: return "\(hours)小时前"
            }
        }

        let days = hours / 24
        if days < 30 {
            switch language {
            case .ja: return "\(days)日前"
            case .en: return "\(days)d ago"
            case .system, .zh: return "\(days)天前"
            }
        }

        return shortDateTime(date)
    }

    static func shortDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Cached template formatters. `DateFormatter` is expensive to build —
    /// `setLocalizedDateFormatFromTemplate` runs an ICU pattern lookup each
    /// time — and the conversation list / chat date dividers below format one
    /// per row on every render. Keying by locale+template means we resolve each
    /// pattern once and reuse the formatter for the life of the process. Only
    /// touched from the main actor (project default isolation), so the plain
    /// dictionary needs no extra locking.
    private static var templateFormatters: [String: DateFormatter] = [:]

    static func localizedTemplateString(_ template: String, localeID: String, calendar: Calendar = .current, date: Date) -> String {
        let key = "\(localeID)|\(template)"
        let formatter: DateFormatter
        if let cached = templateFormatters[key] {
            formatter = cached
        } else {
            let made = DateFormatter()
            made.locale = Locale(identifier: localeID)
            made.calendar = calendar
            made.setLocalizedDateFormatFromTemplate(template)
            templateFormatters[key] = made
            formatter = made
        }
        return formatter.string(from: date)
    }

    static func localeID(for language: AppLanguage) -> String {
        switch language {
        case .ja: return "ja_JP"
        case .en: return "en_US"
        case .system, .zh: return "zh_Hans"
        }
    }

    /// Conversation-list timestamp: today → HH:mm, yesterday → 昨天/Yesterday,
    /// within a week → weekday (周一 / Mon), older → date. Mirrors the common
    /// inbox convention and is distinct from the relative "X 分钟前" used in
    /// chat bubbles.
    static func conversationTimestamp(_ date: Date, language: AppLanguage, reference: Date = .now, calendar: Calendar = .current) -> String {
        let localeID = localeID(for: language)
        func formatted(_ pattern: String) -> String {
            localizedTemplateString(pattern, localeID: localeID, calendar: calendar, date: date)
        }
        if calendar.isDateInToday(date) {
            return formatted("Hmm")
        }
        if calendar.isDateInYesterday(date) {
            switch language {
            case .ja: return "昨日"
            case .en: return "Yesterday"
            default:  return "昨天"
            }
        }
        let startToday = calendar.startOfDay(for: reference)
        let startDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startDate, to: startToday).day ?? 0
        if days >= 2 && days < 7 {
            return formatted("EEE")   // 周一 / Mon / 月
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: reference)
        return formatted(sameYear ? "Md" : "yMd")
    }
}
