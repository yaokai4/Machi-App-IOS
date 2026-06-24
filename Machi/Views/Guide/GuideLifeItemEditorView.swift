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
    @State private var recurrence = "monthly"

    private func applyPreset(_ presetType: String) {
        guard let p = model.lifePresets.first(where: { $0.type == presetType }) else { return }
        title = p.label
        recurrence = p.recurrence
        reminderDays = p.reminderDaysBefore
    }

    var body: some View {
        GuidePlannerFormShell(
            title: guideOSText(language, "生活缴费与手续", "生活支払い・手続き", "Life bills"),
            subtitle: guideOSText(language, "房租、学费、水电、网络、手机费、保险、年金、签证、租约截止日统一进日历", "家賃・学費・公共料金・通信・保険・年金・ビザ・契約期限をまとめます", "Rent, tuition, utilities, phone, visa, insurance, and contract deadlines"),
            model: model
        ) {
            // Server preset catalog (spec P1) — selecting a type pre-fills its
            // smart defaults (周期 + 提前提醒天数); falls back to a built-in list.
            Picker(guideOSText(language, "类型", "種類", "Type"), selection: $type) {
                if model.lifePresets.isEmpty {
                    Text(guideOSText(language, "房租", "家賃", "Rent")).tag("rent"); Text(guideOSText(language, "电费", "電気", "Electricity")).tag("electricity"); Text(guideOSText(language, "燃气", "ガス", "Gas")).tag("gas")
                    Text(guideOSText(language, "水费", "水道", "Water")).tag("water"); Text(guideOSText(language, "网络", "ネット", "Internet")).tag("internet"); Text(guideOSText(language, "手机", "携帯", "Phone")).tag("phone")
                    Text(guideOSText(language, "信用卡", "クレカ", "Credit card")).tag("credit_card"); Text(guideOSText(language, "国保", "国保", "Health ins.")).tag("kokumin_hoken"); Text(guideOSText(language, "年金", "年金", "Pension")).tag("nenkin")
                    Text(guideOSText(language, "住民税", "住民税", "Resident tax")).tag("juminzei"); Text(guideOSText(language, "在留卡", "在留カード", "Residence card")).tag("zairyu_card"); Text(guideOSText(language, "签证更新", "ビザ更新", "Visa renewal")).tag("visa_renewal")
                } else {
                    ForEach(model.lifePresets) { p in Text(p.label).tag(p.type) }
                }
            }
            .pickerStyle(.menu)
            .onChange(of: type) { _, newValue in applyPreset(newValue) }
            Text(guideOSText(language, "默认周期：\(recurrenceLabel(recurrence)) · 提前 \(reminderDays) 天提醒", "周期：\(recurrenceLabel(recurrence)) · \(reminderDays)日前に通知", "\(recurrenceLabel(recurrence)) · remind \(reminderDays)d before"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            GuideOSTextField(title: "标题", text: $title)
            GuideOSTextField(title: "公司 / 房东 / 机构", text: $provider)
            GuideOSTextField(title: "金额（JPY）", text: $amount)
                .keyboardType(.numberPad)
            DatePicker("截止日期", selection: $dueDate, displayedComponents: .date)
            Stepper("提前 \(reminderDays) 天提醒", value: $reminderDays, in: 0...90)
            GuideOSPrimaryButton(title: model.isSaving ? "添加中" : "添加生活截止日") {
                Task {
                    let ok = await model.createLifeItem(.init(
                        type: type,
                        title: title,
                        provider: provider,
                        amount: Int(amount),
                        currency: "JPY",
                        dueAt: GuideOSDate.iso(dueDate),
                        recurrence: recurrence,
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
                            payments: model.lifePayments[item.id] ?? [],
                            onLoadPayments: { Task { await model.loadLifePayments(itemId: item.id) } },
                            onRecordPayment: { amount, paidAt, method, notes in
                                await model.recordLifePayment(
                                    item: item,
                                    amount: amount,
                                    paidAt: paidAt,
                                    method: method,
                                    notes: notes
                                )
                            },
                            onDelete: { Task { await model.deleteLifeItem(item) } },
                            onSave: { payload in await model.updateLifeItem(id: item.id, payload: payload) }
                        )
                    }
                }
            }
        }
        .task {
            await model.loadLifePresets()
            if !model.requireLogin() { return }
            await model.loadLifeItems()
            await model.loadTodos(type: "life_payment")
        }
    }
}

private func recurrenceLabel(_ r: String) -> String {
    switch r {
    case "monthly": return "每月"
    case "quarterly": return "每季"
    case "semester": return "每学期"
    case "yearly": return "每年"
    case "once": return "一次性"
    case "weekly": return "每周"
    default: return r
    }
}

/// A saved life item row with amount + due day, plus edit + delete. Deleting
/// also removes its generated payment todos + reminders server-side.
struct GuideOSLifeItemRow: View {
    let item: KaiXGuideLifeItemDTO
    var payments: [KaiXGuideLifePaymentDTO] = []
    var onLoadPayments: (() -> Void)? = nil
    var onRecordPayment: ((_ amount: Int, _ paidAt: String, _ method: String, _ notes: String) async -> Bool)? = nil
    let onDelete: () -> Void
    var onSave: ((KaiXGuideLifeItemPayload) async -> Bool)? = nil
    @State private var confirming = false
    @State private var editing = false
    @State private var showingPayment = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                if onRecordPayment != nil {
                    Button {
                        onLoadPayments?()
                        showingPayment = true
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(KXColor.accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel("记录 \(item.title) 已支付")
                }
                if onSave != nil {
                    Button { editing = true } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
                Button(role: .destructive) { confirming = true } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            GuideAttachmentSection(entityType: "guide_life_item", entityId: item.id, title: "缴费附件")
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
        .sheet(isPresented: $showingPayment) {
            if let onRecordPayment {
                GuideLifePaymentSheet(item: item, payments: payments, onSave: onRecordPayment)
            }
        }
    }
}

private struct GuideLifePaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: KaiXGuideLifeItemDTO
    let payments: [KaiXGuideLifePaymentDTO]
    let onSave: (Int, String, String, String) async -> Bool

    @State private var amount: String
    @State private var paidAt = Date()
    @State private var method: String
    @State private var notes = ""
    @State private var saving = false

    init(
        item: KaiXGuideLifeItemDTO,
        payments: [KaiXGuideLifePaymentDTO],
        onSave: @escaping (Int, String, String, String) async -> Bool
    ) {
        self.item = item
        self.payments = payments
        self.onSave = onSave
        _amount = State(initialValue: item.amount > 0 ? String(item.amount) : "")
        _method = State(initialValue: item.paymentMethod)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("本次支付") {
                    DatePicker("支付日期", selection: $paidAt, displayedComponents: .date)
                    TextField("金额", text: $amount)
                        .keyboardType(.numberPad)
                    TextField("支付方式", text: $method)
                    TextField("备注", text: $notes, axis: .vertical)
                }
                Section("支付历史") {
                    if payments.isEmpty {
                        Text("还没有支付记录。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(payments) { payment in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(GuideOSDate.short(payment.paidAt))
                                        .font(.subheadline.weight(.semibold))
                                    Text(payment.paymentMethod.isEmpty ? "未注明方式" : payment.paymentMethod)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(payment.currency) \(payment.amount)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(KXColor.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("记录已支付")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "保存") {
                        Task {
                            saving = true
                            let ok = await onSave(Int(amount) ?? 0, GuideOSDate.iso(paidAt), method, notes)
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving)
                }
            }
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
