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
}
