import SwiftUI

struct GuideApplicationPlannerView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideTodoViewModel()
    // Four tracks (spec iOS sync): each maps to a (type, careerTrack) pair so the
    // backend picks the right milestone ladder (出愿 / 新卒 / 转职 / JLPT).
    @State private var track = "school"
    @State private var name = ""
    @State private var department = ""
    @State private var position = ""
    // Default ~90 days out, not today: the backend back-plans the T-90→T-0
    // ladder from this date, so a today default would make every milestone overdue.
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
    @State private var interview = Date()
    @State private var hasInterview = false
    @State private var notes = ""

    private var apiType: String {
        switch track {
        case "school": return "school"
        case "jlpt": return "jlpt"
        default: return "company"
        }
    }
    private var careerTrack: String? { track == "shinsotsu" ? "shinsotsu" : (track == "tenshoku" ? "tenshoku" : nil) }
    private var isSchool: Bool { track == "school" }
    private var isJlpt: Bool { track == "jlpt" }

    var body: some View {
        GuidePlannerFormShell(
            title: guideOSText(language, "出愿 / ES / 面试计划", "出願 / ES / 面接計画", "Applications"),
            subtitle: guideOSText(language, "大学出愿、新卒就活、社会人转职、JLPT 考试全部生成 Todo 和日历项", "大学出願・新卒・転職・JLPTをTodoとカレンダーにします", "Turn applications, ES deadlines, interviews, and exams into todos"),
            model: model
        ) {
            Picker(guideOSText(language, "类型", "種類", "Type"), selection: $track) {
                Text(guideOSText(language, "学校出愿", "学校出願", "School")).tag("school")
                Text(guideOSText(language, "新卒就活", "新卒就活", "New grad")).tag("shinsotsu")
                Text(guideOSText(language, "社会人转职", "社会人転職", "Career change")).tag("tenshoku")
                Text(guideOSText(language, "JLPT 考试", "JLPT 試験", "JLPT")).tag("jlpt")
            }
            .pickerStyle(.segmented)
            if isJlpt {
                GuideOSTextField(title: guideOSText(language, "考试名称（如 JLPT N2）", "試験名（例: JLPT N2）", "Exam name (e.g. JLPT N2)"), text: $name)
            } else {
                GuideOSLibraryPickerField(type: apiType, text: $name)
            }
            if !isJlpt {
                GuideOSTextField(title: isSchool ? "研究科 / 学部" : "部门 / 岗位方向", text: $department)
                GuideOSTextField(title: "职位 / 教授 / 备注对象", text: $position)
            }
            DatePicker(isSchool ? "出愿截止" : (isJlpt ? "考试日期" : "ES 截止"), selection: $deadline, displayedComponents: .date)
            if !isJlpt {
                Toggle("已有面试时间", isOn: $hasInterview)
                if hasInterview {
                    DatePicker("面试日期", selection: $interview, displayedComponents: .date)
                }
            }
            GuideOSTextField(title: "备注", text: $notes)
            GuideOSPrimaryButton(title: model.isSaving ? "添加中" : "添加申请计划") {
                Task {
                    let ok = await model.createApplication(.init(
                        type: apiType,
                        name: name,
                        department: department,
                        position: position,
                        deadline: GuideOSDate.iso(deadline),
                        interviewAt: (!isJlpt && hasInterview) ? GuideOSDate.iso(interview) : nil,
                        notes: notes,
                        careerTrack: careerTrack
                    ))
                    if ok {
                        name = ""
                        department = ""
                        position = ""
                        notes = ""
                    }
                }
            }
        } savedSection: {
            if !model.applications.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(guideOSText(language, "我的申请", "マイ申請", "My applications"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    ForEach(model.applications) { app in
                        GuideOSApplicationRow(
                            app: app,
                            onDelete: { Task { await model.deleteApplication(app) } },
                            onSave: { payload in await model.updateApplication(id: app.id, payload: payload) }
                        )
                    }
                }
            }
        }
        .task {
            if !model.requireLogin() { return }
            await model.loadApplications()
            await model.loadTodos(status: "open")
        }
    }
}

/// A saved application row with its key dates + a delete button. Deleting the
/// application also clears its generated reverse-countdown todos + reminders
/// server-side. A confirmation dialog guards against accidental loss.
struct GuideOSApplicationRow: View {
    let app: KaiXGuideApplicationDTO
    let onDelete: () -> Void
    var onSave: ((KaiXGuideApplicationPayload) async -> Bool)? = nil
    @State private var confirming = false
    @State private var editing = false

    private var isSchool: Bool { app.type == "school" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSchool ? "graduationcap.fill" : "briefcase.fill")
                .font(.subheadline)
                .foregroundStyle(KXColor.accent)
                .frame(width: 30, height: 30)
                .background(KXColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
                let sub = isSchool ? app.department : app.position
                if !sub.isEmpty {
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let d = app.deadline, !d.isEmpty { GuideOSDeleteCardChip(text: (isSchool ? "出愿 " : "ES ") + GuideOSDate.short(d)) }
                    if let i = app.interviewAt, !i.isEmpty { GuideOSDeleteCardChip(text: "面试 " + GuideOSDate.short(i)) }
                    if let r = app.resultAt, !r.isEmpty { GuideOSDeleteCardChip(text: "结果 " + GuideOSDate.short(r)) }
                }
            }
            Spacer(minLength: 0)
            if onSave != nil {
                Button { editing = true } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
        .contentShape(Rectangle())
            }
            Button(role: .destructive) { confirming = true } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        .contentShape(Rectangle())
        }
        .padding(12)
        .kxGlassSurface(radius: 16)
        .confirmationDialog("删除该申请？", isPresented: $confirming, titleVisibility: .visible) {
            Button("删除（含倒排待办）", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $editing) {
            if let onSave { GuideApplicationEditorSheet(app: app, onSave: onSave) }
        }
    }
}

/// In-place editor for a saved application (spec §十三 GuideApplicationEditorView).
/// Server-first: Save calls PATCH /api/guide/applications/:id and the parent
/// reloads from the server.
struct GuideApplicationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let app: KaiXGuideApplicationDTO
    let onSave: (KaiXGuideApplicationPayload) async -> Bool

    @State private var name: String
    @State private var detail: String
    @State private var deadline: Date
    @State private var hasDeadline: Bool
    @State private var interview: Date
    @State private var hasInterview: Bool
    @State private var notes: String
    @State private var saving = false

    init(app: KaiXGuideApplicationDTO, onSave: @escaping (KaiXGuideApplicationPayload) async -> Bool) {
        self.app = app
        self.onSave = onSave
        _name = State(initialValue: app.name)
        _detail = State(initialValue: app.type == "school" ? app.department : app.position)
        _deadline = State(initialValue: GuideOSDate.parse(app.deadline) ?? Date())
        _hasDeadline = State(initialValue: !(app.deadline ?? "").isEmpty)
        _interview = State(initialValue: GuideOSDate.parse(app.interviewAt) ?? Date())
        _hasInterview = State(initialValue: !(app.interviewAt ?? "").isEmpty)
        _notes = State(initialValue: app.notes)
    }

    private var isSchool: Bool { app.type == "school" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GuideOSLibraryPickerField(type: app.type, text: $name)
                    TextField(isSchool ? "研究科 / 学部" : "部门 / 岗位方向", text: $detail)
                }
                Section {
                    Toggle(isSchool ? "出愿截止" : "ES 截止", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("日期", selection: $deadline, displayedComponents: .date) }
                    Toggle("面试时间", isOn: $hasInterview)
                    if hasInterview { DatePicker("日期", selection: $interview, displayedComponents: .date) }
                }
                Section { TextField("备注", text: $notes, axis: .vertical) }
            }
            .navigationTitle("编辑申请")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "保存") {
                        Task {
                            saving = true
                            let ok = await onSave(.init(
                                planId: app.planId.isEmpty ? nil : app.planId,
                                type: app.type,
                                name: name,
                                department: isSchool ? detail : app.department,
                                position: isSchool ? app.position : detail,
                                deadline: hasDeadline ? GuideOSDate.iso(deadline) : "",
                                interviewAt: hasInterview ? GuideOSDate.iso(interview) : "",
                                resultAt: app.resultAt,
                                notes: notes
                            ))
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct GuideOSLibrarySuggestion: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
}

/// Name field that supports BOTH free typing AND picking from the server school
/// / company library — mirrors the Web `LibraryPickerField`. Type ≥2 chars and
/// matches from the库 surface as tappable suggestions; "库里没有？直接输入即可"
/// keeps manual entry first-class. Pure presentation over the existing
/// `guideSearch` endpoint — no local DB, server-first.
struct GuideOSLibraryPickerField: View {
    @Environment(\.appLanguage) private var language
    let type: String      // "school" | "company"
    @Binding var text: String

    @State private var suggestions: [GuideOSLibrarySuggestion] = []
    @State private var isSearching = false
    @State private var justPicked = false

    private var label: String {
        type == "school"
            ? guideOSText(language, "学校 / 研究科名称", "学校・研究科名", "School / graduate program")
            : guideOSText(language, "公司名称", "会社名", "Company name")
    }
    private var placeholder: String {
        type == "school"
            ? guideOSText(language, "输入或从学校库选择，如 东京大学大学院", "学校ライブラリから選択・入力（例：東京大学大学院）", "Type or pick from the school library")
            : guideOSText(language, "输入或从公司库选择，如 Mercari", "会社ライブラリから選択・入力（例：Mercari）", "Type or pick from the company library")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                if isSearching {
                    ProgressView().controlSize(.mini)
                } else if !text.isEmpty {
                    Button {
                        text = ""
                        suggestions = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            justPicked = true
                            text = suggestion.name
                            suggestions = []
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: type == "school" ? "graduationcap.fill" : "building.2.fill")
                                    .font(.caption)
                                    .foregroundStyle(KXColor.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(suggestion.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
        .contentShape(Rectangle())
                        if index < suggestions.count - 1 {
                            Divider().padding(.leading, 32)
                        }
                    }
                    Text(guideOSText(language, "库里没有？直接输入名称即可", "ライブラリに無ければそのまま入力でOK", "Not in the library? Just type the name"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(KXColor.accent.opacity(0.18), lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: suggestions)
        .task(id: "\(type)|\(text)") { await runSearch() }
    }

    private func runSearch() async {
        // A tap just filled the field — swallow exactly one re-trigger so the
        // dropdown doesn't immediately reopen on the chosen name.
        if justPicked { justPicked = false; return }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { suggestions = []; isSearching = false; return }
        // Debounce keystrokes; .task(id:) cancels the previous run for us.
        try? await Task.sleep(nanoseconds: 280_000_000)
        if Task.isCancelled { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let scope = type == "school" ? "schools" : "companies"
            let resp = try await KaiXAPIClient.shared.guideSearch(language: currentGuideOSLanguage(), keyword: query, scope: scope)
            if Task.isCancelled { return }
            if type == "school" {
                suggestions = (resp.groups.schools ?? []).prefix(6).map {
                    GuideOSLibrarySuggestion(id: $0.id, name: $0.schoolName, subtitle: $0.prefecture)
                }
            } else {
                suggestions = (resp.groups.companies ?? []).prefix(6).map {
                    GuideOSLibrarySuggestion(id: $0.id, name: $0.companyName, subtitle: $0.industry)
                }
            }
        } catch {
            suggestions = []
        }
    }
}
