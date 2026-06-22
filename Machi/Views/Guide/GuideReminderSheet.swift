import SwiftUI

/// Spec §十三 GuideReminderSheet — pick a reminder date for a todo. Server-first:
/// Save posts to `/api/guide/todos/:id/reminder`; the server `reminderAt` is the
/// source of truth and APNs is the primary delivery channel.
struct GuideReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    let todo: KaiXGuideTodoDTO
    /// Returns true on success so the sheet can dismiss.
    let onSave: (_ reminderAt: String) async -> Bool

    @State private var date: Date
    @State private var saving = false

    init(todo: KaiXGuideTodoDTO, onSave: @escaping (_ reminderAt: String) async -> Bool) {
        self.todo = todo
        self.onSave = onSave
        let initial = GuideOSDate.parse(todo.reminderAt)
            ?? GuideOSDate.parse(todo.displayDate)
            ?? Calendar.current.date(byAdding: .day, value: 1, to: Date())
            ?? Date()
        _date = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(todo.title).font(.subheadline.weight(.bold))
                    if !todo.summary.isEmpty {
                        Text(todo.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    DatePicker(
                        guideOSText(language, "提醒日期", "リマインド日", "Remind me on"),
                        selection: $date,
                        displayedComponents: .date
                    )
                } footer: {
                    Text(guideOSText(language,
                        "到期当天会通过 App 推送提醒。",
                        "当日にアプリ通知でお知らせします。",
                        "You'll get an app push notification on this day."))
                }
            }
            .navigationTitle(guideOSText(language, "设置提醒", "リマインド設定", "Set reminder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(guideOSText(language, "取消", "キャンセル", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? guideOSText(language, "保存中", "保存中", "Saving") : guideOSText(language, "保存", "保存", "Save")) {
                        Task {
                            saving = true
                            let ok = await onSave(GuideOSDate.iso(date))
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
