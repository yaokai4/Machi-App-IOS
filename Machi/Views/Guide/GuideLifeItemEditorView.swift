import SwiftUI

struct GuideLifePlannerView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideTodoViewModel()
    @State private var type = "rent"
    @State private var title = "房租"
    @State private var provider = ""
    @State private var amount = ""
    @State private var dueDate = Date()
    @State private var reminderDays = 3

    var body: some View {
        GuidePlannerFormShell(
            title: guideOSText(language, "生活缴费与手续", "生活支払い・手続き", "Life bills"),
            subtitle: guideOSText(language, "房租、学费、水电、网络、手机费、保险、年金、签证、租约截止日统一进日历", "家賃・学費・公共料金・通信・保険・年金・ビザ・契約期限をまとめます", "Rent, tuition, utilities, phone, visa, insurance, and contract deadlines"),
            model: model
        ) {
            Picker("类型", selection: $type) {
                Text("房租").tag("rent")
                Text("电费").tag("electric")
                Text("燃气").tag("gas")
                Text("水费").tag("water")
                Text("网络").tag("internet")
                Text("手机").tag("phone")
                Text("学费").tag("tuition")
                Text("交通").tag("transport")
                Text("信用卡").tag("credit_card")
                Text("保险").tag("insurance")
                Text("年金").tag("pension")
                Text("签证").tag("visa")
            }
            .pickerStyle(.menu)
            GuideOSTextField(title: "标题", text: $title)
            GuideOSTextField(title: "公司 / 房东 / 机构", text: $provider)
            GuideOSTextField(title: "金额（JPY）", text: $amount)
                .keyboardType(.numberPad)
            DatePicker("截止日期", selection: $dueDate, displayedComponents: .date)
            Stepper("提前 \(reminderDays) 天提醒", value: $reminderDays, in: 0...30)
            GuideOSPrimaryButton(title: model.isSaving ? "添加中" : "添加生活截止日") {
                Task {
                    let ok = await model.createLifeItem(.init(
                        type: type,
                        title: title,
                        provider: provider,
                        amount: Int(amount),
                        currency: "JPY",
                        dueAt: GuideOSDate.iso(dueDate),
                        recurrence: "monthly",
                        reminderDaysBefore: reminderDays
                    ))
                    if ok {
                        provider = ""
                        amount = ""
                    }
                }
            }
        } savedSection: {
            if !model.lifeItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(guideOSText(language, "我的生活事项", "マイ生活項目", "My life items"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    ForEach(model.lifeItems) { item in
                        GuideOSLifeItemRow(
                            item: item,
                            onDelete: { Task { await model.deleteLifeItem(item) } },
                            onSave: { payload in await model.updateLifeItem(id: item.id, payload: payload) }
                        )
                    }
                }
            }
        }
        .task {
            if !model.requireLogin() { return }
            await model.loadLifeItems()
            await model.loadTodos(type: "life_payment")
        }
    }
}

/// A saved life item row with amount + due day, plus edit + delete. Deleting
/// also removes its generated payment todos + reminders server-side.
struct GuideOSLifeItemRow: View {
    let item: KaiXGuideLifeItemDTO
    let onDelete: () -> Void
    var onSave: ((KaiXGuideLifeItemPayload) async -> Bool)? = nil
    @State private var confirming = false
    @State private var editing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "yensign.circle.fill")
                .font(.subheadline)
                .foregroundStyle(KXColor.accent)
                .frame(width: 30, height: 30)
                .background(KXColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
                if !item.provider.isEmpty {
                    Text(item.provider).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if item.amount > 0 { GuideOSDeleteCardChip(text: "\(item.currency.isEmpty ? "JPY" : item.currency) \(item.amount)") }
                    if item.dueDay > 0 {
                        GuideOSDeleteCardChip(text: "每月 \(item.dueDay) 号")
                    } else if let d = item.dueAt, !d.isEmpty {
                        GuideOSDeleteCardChip(text: GuideOSDate.short(d))
                    }
                    if !item.paymentMethod.isEmpty { GuideOSDeleteCardChip(text: item.paymentMethod) }
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
        .confirmationDialog("删除该生活事项？", isPresented: $confirming, titleVisibility: .visible) {
            Button("删除（含待办）", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $editing) {
            if let onSave { GuideLifeItemEditorSheet(item: item, onSave: onSave) }
        }
    }
}

/// In-place editor for a saved life item (spec §十三 GuideLifeItemEditorView).
struct GuideLifeItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: KaiXGuideLifeItemDTO
    let onSave: (KaiXGuideLifeItemPayload) async -> Bool

    @State private var title: String
    @State private var provider: String
    @State private var amount: String
    @State private var dueDay: Int
    @State private var reminderDays: Int
    @State private var paymentMethod: String
    @State private var saving = false

    init(item: KaiXGuideLifeItemDTO, onSave: @escaping (KaiXGuideLifeItemPayload) async -> Bool) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item.title)
        _provider = State(initialValue: item.provider)
        _amount = State(initialValue: item.amount > 0 ? String(item.amount) : "")
        _dueDay = State(initialValue: max(0, min(31, item.dueDay)))
        _reminderDays = State(initialValue: max(0, min(30, item.reminderDaysBefore)))
        _paymentMethod = State(initialValue: item.paymentMethod)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $title)
                    TextField("公司 / 房东 / 机构", text: $provider)
                    TextField("金额（JPY）", text: $amount).keyboardType(.numberPad)
                    TextField("支付方式", text: $paymentMethod)
                }
                Section {
                    Stepper("每月 \(dueDay) 号", value: $dueDay, in: 0...31)
                    Stepper("提前 \(reminderDays) 天提醒", value: $reminderDays, in: 0...30)
                }
            }
            .navigationTitle("编辑生活事项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "保存") {
                        Task {
                            saving = true
                            let ok = await onSave(.init(
                                type: item.type,
                                title: title,
                                provider: provider,
                                amount: Int(amount) ?? 0,
                                currency: item.currency.isEmpty ? "JPY" : item.currency,
                                paymentMethod: paymentMethod,
                                dueDay: dueDay,
                                dueAt: nil,
                                recurrence: item.recurrence.isEmpty ? "monthly" : item.recurrence,
                                reminderDaysBefore: reminderDays
                            ))
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
