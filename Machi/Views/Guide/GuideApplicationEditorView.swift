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
    @State private var viewMode = "board"
    @State private var websiteURL = ""
    @State private var interviewLocation = ""
    @State private var meetingURL = ""
    @State private var contactName = ""
    @State private var contactEmail = ""
    @State private var priority = "normal"
    @State private var favorite = false
    @State private var tagsText = ""

    private var apiType: String {
        switch track {
        case "new_grad", "career_change": return "company"
        case "jlpt": return "jlpt"
        default: return track
        }
    }
    private var careerTrack: String? { track == "new_grad" ? "shinsotsu" : (track == "career_change" ? "tenshoku" : nil) }
    private var isSchool: Bool { ["school", "vocational", "language_school", "scholarship"].contains(track) }
    private var isJlpt: Bool { track == "jlpt" }

    var body: some View {
        GuidePlannerFormShell(
            title: guideOSText(language, "出愿 / ES / 面试计划", "出願 / ES / 面接計画", "Applications"),
            subtitle: guideOSText(language, "大学出愿、新卒就活、社会人转职、JLPT 考试全部生成 Todo 和日历项", "大学出願・新卒・転職・JLPTをTodoとカレンダーにします", "Turn applications, ES deadlines, interviews, and exams into todos"),
            model: model
        ) {
            Picker(guideOSText(language, "类型", "種類", "Type"), selection: $track) {
                Text(guideOSText(language, "大学 / 大学院", "大学・大学院", "University")).tag("school")
                Text(guideOSText(language, "专门学校", "専門学校", "Vocational")).tag("vocational")
                Text(guideOSText(language, "语言学校", "日本語学校", "Language school")).tag("language_school")
                Text(guideOSText(language, "新卒就活", "新卒就活", "New grad")).tag("new_grad")
                Text(guideOSText(language, "社会人转职", "社会人転職", "Career change")).tag("career_change")
                Text(guideOSText(language, "实习", "インターン", "Internship")).tag("internship")
                Text(guideOSText(language, "奖学金", "奨学金", "Scholarship")).tag("scholarship")
                Text(guideOSText(language, "签证申请", "ビザ申請", "Visa")).tag("visa")
                Text(guideOSText(language, "JLPT 考试", "JLPT 試験", "JLPT")).tag("jlpt")
                Text(guideOSText(language, "其他", "その他", "Other")).tag("other")
            }
            .pickerStyle(.menu)
            if isJlpt {
                GuideOSTextField(title: guideOSText(language, "考试名称（如 JLPT N2）", "試験名（例: JLPT N2）", "Exam name (e.g. JLPT N2)"), text: $name)
            } else if track == "visa" || track == "other" {
                // 签证/其他没有对应的学校/公司库 — a plain field, not a picker that
                // would confusingly suggest companies for a visa application.
                GuideOSTextField(title: guideOSText(language, "申请名称 / 对象", "申請名・対象", "Application name / target"), text: $name)
            } else {
                // Semantic picker type: 语言学校/专门学校/奖学金 search the school
                // library (not the company库 the raw apiType used to hit).
                GuideOSLibraryPickerField(type: isSchool ? "school" : "company", text: $name)
            }
            if !isJlpt {
                GuideOSTextField(title: isSchool ? guideOSText(language, "研究科 / 学部", "研究科・学部", "Faculty / graduate school") : guideOSText(language, "部门 / 岗位方向", "部署・職種", "Department / role"), text: $department)
                GuideOSTextField(title: guideOSText(language, "职位 / 教授 / 备注对象", "職位・教授・対象", "Position / professor / contact"), text: $position)
            }
            DatePicker(isSchool ? guideOSText(language, "出愿截止", "出願締切", "Application deadline") : (isJlpt ? guideOSText(language, "考试日期", "試験日", "Exam date") : guideOSText(language, "ES 截止", "ES締切", "ES deadline")), selection: $deadline, displayedComponents: .date)
            if !isJlpt {
                Toggle(guideOSText(language, "已有面试时间", "面接日が決定済み", "Interview scheduled"), isOn: $hasInterview)
                if hasInterview {
                    DatePicker(guideOSText(language, "面试日期", "面接日", "Interview date"), selection: $interview, displayedComponents: .date)
                }
            }
            Picker(guideOSText(language, "优先级", "優先度", "Priority"), selection: $priority) {
                Text(guideOSText(language, "高", "高", "High")).tag("high")
                Text(guideOSText(language, "普通", "普通", "Normal")).tag("normal")
                Text(guideOSText(language, "低", "低", "Low")).tag("low")
            }
            .pickerStyle(.menu)
            Toggle(guideOSText(language, "重点关注", "重点フォロー", "Highlight"), isOn: $favorite)
            GuideOSTextField(title: guideOSText(language, "官网 / 招聘页", "公式サイト・採用ページ", "Website / careers page"), text: $websiteURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            if !isJlpt {
                GuideOSTextField(title: guideOSText(language, "面试地点", "面接場所", "Interview location"), text: $interviewLocation)
                GuideOSTextField(title: guideOSText(language, "线上会议链接", "オンライン会議リンク", "Online meeting link"), text: $meetingURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            HStack {
                GuideOSTextField(title: guideOSText(language, "联系人", "担当者", "Contact"), text: $contactName)
                GuideOSTextField(title: guideOSText(language, "联系邮箱", "連絡先メール", "Contact email"), text: $contactEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }
            GuideOSTextField(title: guideOSText(language, "标签（逗号分隔）", "タグ（カンマ区切り）", "Tags (comma-separated)"), text: $tagsText)
            GuideOSTextField(title: guideOSText(language, "备注", "メモ", "Notes"), text: $notes)
            GuideOSPrimaryButton(title: model.isSaving ? guideOSText(language, "添加中", "追加中", "Adding") : guideOSText(language, "添加申请计划", "申請計画を追加", "Add application plan")) {
                Task {
                    let ok = await model.createApplication(.init(
                        type: apiType,
                        name: name,
                        department: department,
                        position: position,
                        deadline: GuideOSDate.iso(deadline),
                        interviewAt: (!isJlpt && hasInterview) ? GuideOSDate.iso(interview) : nil,
                        notes: notes,
                        careerTrack: careerTrack,
                        stage: "saved",
                        websiteUrl: websiteURL,
                        interviewLocation: interviewLocation,
                        meetingUrl: meetingURL,
                        contactName: contactName,
                        contactEmail: contactEmail,
                        priority: priority,
                        favorite: favorite,
                        tags: tagsText
                            .split(whereSeparator: { $0 == "," || $0 == "，" })
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    ))
                    if ok {
                        name = ""
                        department = ""
                        position = ""
                        notes = ""
                        websiteURL = ""
                        interviewLocation = ""
                        meetingURL = ""
                        contactName = ""
                        contactEmail = ""
                        tagsText = ""
                        favorite = false
                    }
                }
            }
        } savedSection: {
            if !model.applications.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(guideOSText(language, "我的申请", "マイ申請", "My applications"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(model.applications.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                    }
                    Picker(guideOSText(language, "视图", "表示", "View"), selection: $viewMode) {
                        Text(guideOSText(language, "看板", "ボード", "Board")).tag("board")
                        Text(guideOSText(language, "列表", "リスト", "List")).tag("list")
                    }
                    .pickerStyle(.segmented)

                    if viewMode == "board" {
                        GuideApplicationBoard(
                            applications: model.applications,
                            onDelete: { app in Task { await model.deleteApplication(app) } },
                            onSave: { app, payload in await model.updateApplication(id: app.id, payload: payload) }
                        )
                    } else {
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
        }
        .task {
            // The bottom todo strip should only show application-generated
            // todos (出愿/ES/面试倒排), not 房租/背单词 from other planners.
            model.todoSourceTypeFilter = ["application"]
            // 游客可以随意浏览；登录墙只在保存时弹（工作台承诺「保存时再登录」）。
            guard model.isLoggedIn else { return }
            await model.loadApplications()
            await model.loadTodos(status: "open")
        }
    }
}

/// A saved application row with its key dates + a delete button. Deleting the
/// application also clears its generated reverse-countdown todos + reminders
/// server-side. A confirmation dialog guards against accidental loss.
struct GuideOSApplicationRow: View {
    @Environment(\.appLanguage) private var language
    let app: KaiXGuideApplicationDTO
    let onDelete: () -> Void
    var onSave: ((KaiXGuideApplicationPayload) async -> Bool)? = nil
    @State private var confirming = false
    @State private var editing = false

    private var isSchool: Bool { app.type == "school" }
    private var stage: String { app.stage ?? "saved" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSchool ? "graduationcap.fill" : "briefcase.fill")
                .font(.subheadline)
                .foregroundStyle(KXColor.accent)
                .frame(width: 30, height: 30)
                .background(KXColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(app.name).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
                    if app.favorite == true {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                let sub = isSchool ? app.department : app.position
                if !sub.isEmpty {
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    GuideOSDeleteCardChip(text: guideApplicationStageTitle(stage, language))
                    if let d = app.deadline, !d.isEmpty { GuideOSDeleteCardChip(text: (isSchool ? guideOSText(language, "出愿 ", "出願 ", "Apply ") : guideOSText(language, "ES ", "ES ", "ES ")) + GuideOSDate.short(d)) }
                    if let i = app.interviewAt, !i.isEmpty { GuideOSDeleteCardChip(text: guideOSText(language, "面试 ", "面接 ", "Interview ") + GuideOSDate.short(i)) }
                    if let r = app.resultAt, !r.isEmpty { GuideOSDeleteCardChip(text: guideOSText(language, "结果 ", "結果 ", "Result ") + GuideOSDate.short(r)) }
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
                .buttonStyle(.fullArea)
                .contentShape(Rectangle())
                .accessibilityLabel(guideOSText(language, "编辑 \(app.name)", "\(app.name)を編集", "Edit \(app.name)"))
            }
            Button(role: .destructive) { confirming = true } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.fullArea)
            .contentShape(Rectangle())
            .accessibilityLabel(guideOSText(language, "删除 \(app.name)", "\(app.name)を削除", "Delete \(app.name)"))
        }
        .padding(12)
        .kxGlassSurface(radius: KXRadius.md)
        .confirmationDialog(guideOSText(language, "删除该申请？", "この申請を削除しますか？", "Delete this application?"), isPresented: $confirming, titleVisibility: .visible) {
            Button(guideOSText(language, "删除（含倒排待办）", "削除（逆算ToDoも含む）", "Delete (incl. countdown todos)"), role: .destructive, action: onDelete)
            Button(guideOSText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
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
    @Environment(\.appLanguage) private var language
    let app: KaiXGuideApplicationDTO
    let onSave: (KaiXGuideApplicationPayload) async -> Bool

    @State private var name: String
    @State private var detail: String
    @State private var deadline: Date
    @State private var hasDeadline: Bool
    @State private var interview: Date
    @State private var hasInterview: Bool
    @State private var notes: String
    @State private var stage: String
    @State private var priority: String
    @State private var websiteURL: String
    @State private var interviewLocation: String
    @State private var meetingURL: String
    @State private var contactName: String
    @State private var contactEmail: String
    @State private var favorite: Bool
    @State private var saving = false

    init(app: KaiXGuideApplicationDTO, onSave: @escaping (KaiXGuideApplicationPayload) async -> Bool) {
        self.app = app
        self.onSave = onSave
        _name = State(initialValue: app.name)
        let schoolish = ["school", "vocational", "language_school", "scholarship"].contains(app.type)
        _detail = State(initialValue: schoolish ? app.department : app.position)
        _deadline = State(initialValue: GuideOSDate.parse(app.deadline) ?? Date())
        _hasDeadline = State(initialValue: !(app.deadline ?? "").isEmpty)
        _interview = State(initialValue: GuideOSDate.parse(app.interviewAt) ?? Date())
        _hasInterview = State(initialValue: !(app.interviewAt ?? "").isEmpty)
        _notes = State(initialValue: app.notes)
        _stage = State(initialValue: app.stage ?? "saved")
        _priority = State(initialValue: app.priority ?? "normal")
        _websiteURL = State(initialValue: app.websiteUrl ?? "")
        _interviewLocation = State(initialValue: app.interviewLocation ?? "")
        _meetingURL = State(initialValue: app.meetingUrl ?? "")
        _contactName = State(initialValue: app.contactName ?? "")
        _contactEmail = State(initialValue: app.contactEmail ?? "")
        _favorite = State(initialValue: app.favorite ?? false)
    }

    // Match the planner's grouping so 语言学校/专门学校/奖学金 read as schools
    // (labels + which field `detail` maps to) instead of falling into 公司.
    private var isSchool: Bool { ["school", "vocational", "language_school", "scholarship"].contains(app.type) }
    private var usesLibraryPicker: Bool { !["visa", "other", "jlpt"].contains(app.type) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if usesLibraryPicker {
                        GuideOSLibraryPickerField(type: isSchool ? "school" : "company", text: $name)
                    } else {
                        TextField(guideOSText(language, "申请名称 / 对象", "申請名・対象", "Application name / target"), text: $name)
                    }
                    TextField(isSchool ? guideOSText(language, "研究科 / 学部", "研究科・学部", "Faculty / graduate school") : guideOSText(language, "部门 / 岗位方向", "部署・職種", "Department / role"), text: $detail)
                }
                Section(guideOSText(language, "进度", "進捗", "Progress")) {
                    Picker(guideOSText(language, "当前阶段", "現在のステージ", "Current stage"), selection: $stage) {
                        ForEach(guideApplicationStages, id: \.key) { item in
                            Text(guideApplicationStageTitle(item.key, language)).tag(item.key)
                        }
                    }
                    Picker(guideOSText(language, "优先级", "優先度", "Priority"), selection: $priority) {
                        Text(guideOSText(language, "高", "高", "High")).tag("high")
                        Text(guideOSText(language, "普通", "普通", "Normal")).tag("normal")
                        Text(guideOSText(language, "低", "低", "Low")).tag("low")
                    }
                    Toggle(guideOSText(language, "重点关注", "重点フォロー", "Highlight"), isOn: $favorite)
                }
                Section {
                    Toggle(isSchool ? guideOSText(language, "出愿截止", "出願締切", "Application deadline") : guideOSText(language, "ES 截止", "ES締切", "ES deadline"), isOn: $hasDeadline)
                    if hasDeadline { DatePicker(guideOSText(language, "日期", "日付", "Date"), selection: $deadline, displayedComponents: .date) }
                    Toggle(guideOSText(language, "面试时间", "面接日時", "Interview date"), isOn: $hasInterview)
                    if hasInterview { DatePicker(guideOSText(language, "日期", "日付", "Date"), selection: $interview, displayedComponents: .date) }
                }
                Section(guideOSText(language, "链接与联系人", "リンクと連絡先", "Links & contact")) {
                    TextField(guideOSText(language, "官网 / 招聘页", "公式サイト・採用ページ", "Website / careers page"), text: $websiteURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField(guideOSText(language, "面试地点", "面接場所", "Interview location"), text: $interviewLocation)
                    TextField(guideOSText(language, "线上会议链接", "オンライン会議リンク", "Online meeting link"), text: $meetingURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField(guideOSText(language, "联系人", "担当者", "Contact"), text: $contactName)
                    TextField(guideOSText(language, "联系邮箱", "連絡先メール", "Contact email"), text: $contactEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
                Section { TextField(guideOSText(language, "备注", "メモ", "Notes"), text: $notes, axis: .vertical) }
                Section(guideOSText(language, "附件", "添付ファイル", "Attachments")) {
                    GuideAttachmentSection(entityType: "guide_application", entityId: app.id, title: guideOSText(language, "申请附件", "申請の添付", "Application attachments"))
                }
                if let stages = app.stages, !stages.isEmpty {
                    Section(guideOSText(language, "阶段时间线", "ステージのタイムライン", "Stage timeline")) {
                        ForEach(stages) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(KXColor.accent)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(guideApplicationStageTitle(item.stage, language))
                                        .font(.subheadline.weight(.semibold))
                                    if !item.note.isEmpty {
                                        Text(item.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let occurredAt = item.occurredAt {
                                        Text(GuideOSDate.short(occurredAt))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(guideOSText(language, "编辑申请", "申請を編集", "Edit application"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(guideOSText(language, "取消", "キャンセル", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? guideOSText(language, "保存中", "保存中", "Saving") : guideOSText(language, "保存", "保存", "Save")) {
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
                                notes: notes,
                                careerTrack: app.careerTrack,
                                stage: stage,
                                stageNote: stage == app.stage ? nil : guideOSText(language, "在 iOS 更新阶段", "iOSでステージを更新", "Stage updated on iOS"),
                                websiteUrl: websiteURL,
                                interviewLocation: interviewLocation,
                                meetingUrl: meetingURL,
                                contactName: contactName,
                                contactEmail: contactEmail,
                                priority: priority,
                                favorite: favorite,
                                tags: app.tags,
                                status: app.status
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

private let guideApplicationStages: [(key: String, title: String)] = [
    ("saved", "已收藏"),
    ("preparing", "准备中"),
    ("submitted", "已提交"),
    ("es", "ES"),
    ("web_test", "Web Test"),
    ("interview_1", "一面"),
    ("interview_2", "二面"),
    ("final", "最终面"),
    ("offer", "录取 / Offer"),
    ("rejected", "未通过"),
    ("withdrawn", "已撤回")
]

private func guideApplicationStageTitle(_ key: String, _ language: AppLanguage) -> String {
    switch key {
    case "saved": return guideOSText(language, "已收藏", "保存済み", "Saved")
    case "preparing": return guideOSText(language, "准备中", "準備中", "Preparing")
    case "submitted": return guideOSText(language, "已提交", "提出済み", "Submitted")
    case "es": return "ES"
    case "web_test": return "Web Test"
    case "interview_1": return guideOSText(language, "一面", "一次面接", "1st interview")
    case "interview_2": return guideOSText(language, "二面", "二次面接", "2nd interview")
    case "final": return guideOSText(language, "最终面", "最終面接", "Final interview")
    case "offer": return guideOSText(language, "录取 / Offer", "内定・Offer", "Offer")
    case "rejected": return guideOSText(language, "未通过", "不合格", "Rejected")
    case "withdrawn": return guideOSText(language, "已撤回", "辞退", "Withdrawn")
    default: return guideOSText(language, "已收藏", "保存済み", "Saved")
    }
}

private struct GuideApplicationBoard: View {
    @Environment(\.appLanguage) private var language
    let applications: [KaiXGuideApplicationDTO]
    let onDelete: (KaiXGuideApplicationDTO) -> Void
    let onSave: (KaiXGuideApplicationDTO, KaiXGuideApplicationPayload) async -> Bool

    private var visibleStages: [(key: String, title: String)] {
        guideApplicationStages.filter { stage in
            stage.key == "saved" ||
            stage.key == "preparing" ||
            stage.key == "submitted" ||
            stage.key == "es" ||
            stage.key == "interview_1" ||
            stage.key == "offer" ||
            applications.contains { ($0.stage ?? "saved") == stage.key }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(visibleStages, id: \.key) { stage in
                    let items = applications.filter { ($0.stage ?? "saved") == stage.key }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(guideApplicationStageTitle(stage.key, language))
                                .font(.caption.weight(.bold))
                            Spacer()
                            Text("\(items.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 2)

                        if items.isEmpty {
                            Text(guideOSText(language, "暂无", "なし", "None"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            ForEach(items) { app in
                                GuideOSApplicationRow(
                                    app: app,
                                    onDelete: { onDelete(app) },
                                    onSave: { payload in await onSave(app, payload) }
                                )
                            }
                        }
                    }
                    .frame(width: 286)
                }
            }
            .padding(.vertical, 2)
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
                    .buttonStyle(.fullArea)
        .contentShape(Rectangle())
                    .accessibilityLabel(guideOSText(language, "清除", "クリア", "Clear"))
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
                        .buttonStyle(.fullArea)
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
