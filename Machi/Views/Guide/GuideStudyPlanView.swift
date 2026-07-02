import SwiftUI

/// Spec P0.2: turn a JLPT target into recurring study habits (每日词汇 / 每周语法
/// / 周末模考 + 错题复盘) plus registration & sprint milestones. Server-first via
/// POST /api/guide/study-plan; the generated todos sync to the plan, calendar
/// and reminders.
struct GuideStudyPlanView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideTodoViewModel()

    @State private var level = "N2"
    @State private var examDate = Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date()
    @State private var dailyMinutes = 45

    private let levels = ["N1", "N2", "N3", "N4", "N5"]

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(
                        title: guideOSText(language, "JLPT 学习计划", "JLPT 学習計画", "JLPT study plan"),
                        subtitle: guideOSText(language, "把考级目标变成每天的学习习惯：词汇、语法、模考、复盘", "目標を毎日の学習習慣に：語彙・文法・模試・復習", "Turn your goal into daily habits: vocab, grammar, mock tests, review")
                    )
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(guideOSText(language, "目标级别", "目標レベル", "Target level")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Picker("", selection: $level) {
                                ForEach(levels, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        DatePicker(guideOSText(language, "考试日期", "試験日", "Exam date"), selection: $examDate, displayedComponents: .date)
                        Stepper(guideOSText(language, "每天学习 \(dailyMinutes) 分钟", "1日 \(dailyMinutes) 分", "\(dailyMinutes) min/day"), value: $dailyMinutes, in: 10...240, step: 5)
                        GuideOSPrimaryButton(title: model.isSaving ? guideOSText(language, "生成中", "生成中", "Generating") : guideOSText(language, "生成学习计划", "計画を生成", "Generate plan")) {
                            Task { _ = await model.generateStudyPlan(level: level, examDate: GuideOSDate.iso(examDate), dailyMinutes: dailyMinutes) }
                        }
                    }
                    .padding(15)
                    .kxGlassSurface(radius: KXRadius.hero)

                    if let message = model.message { GuideOSNotice(message: message) }

                    if !model.studyTodos.isEmpty {
                        Text(guideOSText(language, "已生成 \(model.studyTodos.count) 个学习任务", "\(model.studyTodos.count) 件のタスクを生成", "\(model.studyTodos.count) tasks generated"))
                            .font(.subheadline.weight(.bold))
                        ForEach(model.studyTodos) { todo in
                            GuideStudyTodoRow(todo: todo)
                        }
                    } else {
                        GuideOSEmptyMini(text: guideOSText(language, "生成后会出现每日词汇、每周语法、周末模考等循环任务，并同步到日历和提醒。", "生成すると毎日語彙・毎週文法・週末模試などの繰り返しタスクがカレンダーと通知に同期します。", "Generates recurring vocab/grammar/mock tasks synced to calendar and reminders."))
                    }
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "日语学习计划", "日本語学習計画", "Japanese study plan"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GuideStudyTodoRow: View {
    @Environment(\.appLanguage) private var language
    let todo: KaiXGuideTodoDTO

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: todo.recurrence == nil || todo.recurrence!.isEmpty ? "calendar" : "repeat")
                .font(.subheadline)
                .foregroundStyle(KXColor.accent)
                .frame(width: 30, height: 30)
                .background(KXColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 6) {
                    if let r = todo.recurrenceLabel {
                        Text(guideOSText(language, r + "循环", r + "（繰り返し）", r + " · repeating")).font(.caption2.weight(.bold)).foregroundStyle(KXColor.accent)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(KXColor.accent.opacity(0.12), in: Capsule())
                    } else if let d = todo.displayDate, !d.isEmpty {
                        Text(GuideOSDate.short(d)).font(.caption2).foregroundStyle(.secondary)
                    }
                    if todo.estimatedMinutes > 0 {
                        Text(guideOSText(language, "\(todo.estimatedMinutes) 分", "\(todo.estimatedMinutes) 分", "\(todo.estimatedMinutes) min")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .kxGlassSurface(radius: 16)
    }
}
