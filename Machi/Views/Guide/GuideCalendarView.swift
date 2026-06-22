import SwiftUI

struct GuideCalendarView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideCalendarViewModel()

    private var grouped: [(String, [KaiXGuideCalendarItemDTO])] {
        Dictionary(grouping: model.calendarItems) { $0.date ?? "" }
            .filter { !$0.key.isEmpty }
            .sorted { $0.key < $1.key }
    }

    private var countdowns: [(date: String, title: String, days: Int)] {
        grouped.compactMap { date, items in
            guard let days = GuideCalendarCountdown.daysUntil(date), days >= 0 else { return nil }
            return (date, items.first?.title ?? "\(items.count) 项任务", days)
        }
        .sorted { $0.days < $1.days }
        .prefix(5)
        .map { $0 }
    }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(title: guideOSText(language, "Guide 日历", "Guide カレンダー", "Guide calendar"), subtitle: guideOSText(language, "出愿、ES、面试、JLPT、签证、房租水电都按日期聚合", "出願・ES・面接・JLPT・ビザ・家賃公共料金を日付で整理", "Applications, interviews, exams, visa, and bills by date"))
                    if grouped.isEmpty && !model.isLoading {
                        GuideOSEmptyPanel(title: guideOSText(language, "暂无未来截止日", "今後の期限はありません", "No upcoming deadlines"), subtitle: guideOSText(language, "添加申请或生活缴费后，这里会变成你的日本时间线。", "申請や生活支払いを追加すると、日本生活のタイムラインになります。", "Add applications or life bills to build your timeline."))
                    } else {
                        GuideCalendarCountdownStrip(items: countdowns)
                        ForEach(grouped, id: \.0) { date, items in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(GuideOSDate.short(date))
                                    .font(.headline.weight(.bold))
                                ForEach(items) { item in
                                    if let todo = item.todo {
                                        GuideOSTodoCard(todo: todo) { Task { await model.complete(todo) } }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "日历", "カレンダー", "Calendar"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !model.requireLogin() { return }
            await model.loadCalendar()
        }
        .refreshable { await model.loadCalendar() }
    }
}

private enum GuideCalendarCountdown {
    static func daysUntil(_ raw: String) -> Int? {
        let dateText = String(raw.prefix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let target = formatter.date(from: dateText),
              let today = formatter.date(from: formatter.string(from: Date())) else { return nil }
        return Calendar.current.dateComponents([.day], from: today, to: target).day
    }
}

private struct GuideCalendarCountdownStrip: View {
    let items: [(date: String, title: String, days: Int)]
    @Environment(\.appLanguage) private var language

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(guideOSText(language, "最近倒数", "直近のカウントダウン", "Upcoming countdown"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items, id: \.date) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.days == 0 ? "今天" : "\(item.days) 天")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(item.days <= 3 ? .orange : KXColor.accent)
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                Text(GuideOSDate.short(item.date))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 138, alignment: .leading)
                            .padding(12)
                            .kxGlassSurface(radius: 16)
                        }
                    }
                }
            }
        }
    }
}
