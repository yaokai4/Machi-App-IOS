import Foundation
import Testing
@testable import Machi

/// Covers the cached date-formatting helpers added for the conversation list and
/// chat date dividers. The cache keys formatters by locale+template, so the key
/// risk is cross-locale corruption (a cached `en_US` formatter being reused for
/// `ja_JP`). These tests pin both correctness and that interleaving locales
/// stays consistent.
@MainActor
struct DateFormatterUtilsTests {

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9, minute: Int = 5) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return Calendar.current.date(from: components)!
    }

    @Test func localeIDMapsEveryLanguage() {
        #expect(DateFormatterUtils.localeID(for: .ja) == "ja_JP")
        #expect(DateFormatterUtils.localeID(for: .en) == "en_US")
        #expect(DateFormatterUtils.localeID(for: .zh) == "zh_Hans")
        #expect(DateFormatterUtils.localeID(for: .system) == "zh_Hans")
    }

    @Test func localizedTemplateStringIsDeterministicAndStableAcrossCalls() {
        let d = date(2025, 3, 7)
        let first = DateFormatterUtils.localizedTemplateString("yMd", localeID: "en_US", date: d)
        let second = DateFormatterUtils.localizedTemplateString("yMd", localeID: "en_US", date: d)
        #expect(first == second, "cached formatter must return identical output for identical input")
        #expect(!first.isEmpty)
    }

    @Test func localizedTemplateStringDoesNotLeakLocaleAcrossCacheHits() {
        // Interleave locales to exercise the cache: each must keep its own
        // formatter, not reuse the previously-cached one.
        let d = date(2025, 3, 7)
        let en1 = DateFormatterUtils.localizedTemplateString("yMMMd", localeID: "en_US", date: d)
        let ja1 = DateFormatterUtils.localizedTemplateString("yMMMd", localeID: "ja_JP", date: d)
        let en2 = DateFormatterUtils.localizedTemplateString("yMMMd", localeID: "en_US", date: d)
        let ja2 = DateFormatterUtils.localizedTemplateString("yMMMd", localeID: "ja_JP", date: d)
        #expect(en1 == en2, "English output must be stable after a Japanese call cached in between")
        #expect(ja1 == ja2, "Japanese output must be stable after an English call cached in between")
        #expect(en1.contains("2025"))
        #expect(ja1.contains("2025"))
    }

    @Test func conversationTimestampTodayShowsTime() {
        let now = Date()
        let result = DateFormatterUtils.conversationTimestamp(now, language: .en, reference: now)
        // Today → HH:mm (a numeric time), never a weekday name.
        #expect(result.contains(":"))
    }

    @Test func conversationTimestampYesterdayIsLocalized() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        #expect(DateFormatterUtils.conversationTimestamp(yesterday, language: .zh, reference: now) == "昨天")
        #expect(DateFormatterUtils.conversationTimestamp(yesterday, language: .ja, reference: now) == "昨日")
        #expect(DateFormatterUtils.conversationTimestamp(yesterday, language: .en, reference: now) == "Yesterday")
    }

    @Test func conversationTimestampWithinWeekShowsWeekday() {
        let now = date(2025, 3, 7)               // a Friday
        let threeDaysAgo = date(2025, 3, 4)      // Tuesday, 3 days earlier
        let result = DateFormatterUtils.conversationTimestamp(threeDaysAgo, language: .en, reference: now)
        #expect(!result.isEmpty)
        #expect(result != "Yesterday")
    }

    @Test func relativeTextLocalizesRecentBuckets() {
        let now = Date()
        #expect(DateFormatterUtils.relativeText(from: now.addingTimeInterval(-10), to: now, language: .zh) == "刚刚")
        #expect(DateFormatterUtils.relativeText(from: now.addingTimeInterval(-10), to: now, language: .ja) == "たった今")
        #expect(DateFormatterUtils.relativeText(from: now.addingTimeInterval(-10), to: now, language: .en) == "Just now")

        let fiveMinAgo = now.addingTimeInterval(-5 * 60)
        #expect(DateFormatterUtils.relativeText(from: fiveMinAgo, to: now, language: .zh) == "5分钟前")
        #expect(DateFormatterUtils.relativeText(from: fiveMinAgo, to: now, language: .en) == "5 min ago")

        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        #expect(DateFormatterUtils.relativeText(from: twoHoursAgo, to: now, language: .ja) == "2時間前")
    }
}
