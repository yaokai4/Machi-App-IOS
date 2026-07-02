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
    @State private var paymentMethod = "auto_transfer"
    @State private var autoDebit = true

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
            Text(guideOSText(language, "默认周期：\(recurrenceLabel(language, recurrence)) · 提前 \(reminderDays) 天提醒", "周期：\(recurrenceLabel(language, recurrence)) · \(reminderDays)日前に通知", "\(recurrenceLabel(language, recurrence)) · remind \(reminderDays)d before"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            GuideOSTextField(title: guideOSText(language, "标题", "タイトル", "Title"), text: $title)
            GuideOSTextField(title: guideOSText(language, "公司 / 房东 / 机构", "会社 / 大家 / 機関", "Company / landlord / institution"), text: $provider)
            GuideOSTextField(title: guideOSText(language, "金额（JPY）", "金額（円）", "Amount (JPY)"), text: $amount)
                .keyboardType(.numberPad)
            GuideOSDateField(title: guideOSText(language, "截止日期", "締切日", "Due date"), date: $dueDate)
            Picker(guideOSText(language, "缴费方式", "支払い方法", "Payment"), selection: $paymentMethod) {
                Text(guideOSText(language, "口座振替", "口座振替", "Auto-transfer")).tag("auto_transfer")
                Text(guideOSText(language, "信用卡", "クレカ", "Credit card")).tag("credit_card")
                Text(guideOSText(language, "便利店", "コンビニ", "Konbini")).tag("konbini")
                Text(guideOSText(language, "银行转账", "銀行振込", "Bank transfer")).tag("bank_transfer")
                Text(guideOSText(language, "收信件缴费", "請求書払い", "Invoice")).tag("invoice")
                Text(guideOSText(language, "其他", "その他", "Other")).tag("other")
            }
            .pickerStyle(.menu)
            .onChange(of: paymentMethod) { _, newValue in
                autoDebit = (newValue == "auto_transfer" || newValue == "credit_card")
            }
            Toggle(guideOSText(language, "自动扣款（只提醒核对余额）", "自動引き落とし（残高確認のみ通知）", "Auto-debit (just remind to check balance)"), isOn: $autoDebit)
                .font(.subheadline)
            Stepper(guideOSText(language, "提前 \(reminderDays) 天提醒", "\(reminderDays)日前に通知", "Remind \(reminderDays)d before"), value: $reminderDays, in: 0...90)
            GuideOSPrimaryButton(title: model.isSaving ? guideOSText(language, "添加中", "追加中", "Adding") : guideOSText(language, "添加生活截止日", "生活の締切を追加", "Add life deadline")) {
                Task {
                    let ok = await model.createLifeItem(.init(
                        type: type,
                        title: title,
                        provider: provider,
                        amount: Int(amount),
                        currency: "JPY",
                        paymentMethod: paymentMethod,
                        autoDebit: autoDebit,
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
            // 游客可以随意浏览；登录墙只在保存时弹（工作台承诺「保存时再登录」）。
            guard model.isLoggedIn else { return }
            await model.loadLifeItems()
            await model.loadTodos(type: "life_payment")
        }
    }
}

private func recurrenceLabel(_ language: AppLanguage, _ r: String) -> String {
    switch r {
    case "monthly": return guideOSText(language, "每月", "毎月", "Monthly")
    case "quarterly": return guideOSText(language, "每季", "四半期ごと", "Quarterly")
    case "semester": return guideOSText(language, "每学期", "学期ごと", "Per semester")
    case "yearly": return guideOSText(language, "每年", "毎年", "Yearly")
    case "once": return guideOSText(language, "一次性", "一回のみ", "One-time")
    case "weekly": return guideOSText(language, "每周", "毎週", "Weekly")
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
    @Environment(\.appLanguage) private var language
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
                            GuideOSDeleteCardChip(text: guideOSText(language, "每月 \(item.dueDay) 号", "毎月\(item.dueDay)日", "Day \(item.dueDay) monthly"))
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
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .accessibilityLabel(guideOSText(language, "记录 \(item.title) 已支付", "\(item.title)の支払いを記録", "Mark \(item.title) as paid"))
                }
                if onSave != nil {
                    Button { editing = true } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .accessibilityLabel(guideOSText(language, "编辑 \(item.title)", "\(item.title)を編集", "Edit \(item.title)"))
                }
                Button(role: .destructive) { confirming = true } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.fullArea)
                .contentShape(Rectangle())
                .accessibilityLabel(guideOSText(language, "删除 \(item.title)", "\(item.title)を削除", "Delete \(item.title)"))
            }
            GuideAttachmentSection(entityType: "guide_life_item", entityId: item.id, title: guideOSText(language, "缴费附件", "支払い添付", "Payment attachments"))
        }
        .padding(12)
        .kxGlassSurface(radius: KXRadius.md)
        .confirmationDialog(guideOSText(language, "删除该生活事项？", "この生活項目を削除しますか？", "Delete this life item?"), isPresented: $confirming, titleVisibility: .visible) {
            Button(guideOSText(language, "删除（含待办）", "削除（タスクも含む）", "Delete (incl. todos)"), role: .destructive, action: onDelete)
            Button(guideOSText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
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
    @Environment(\.appLanguage) private var language
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
                Section(guideOSText(language, "本次支付", "今回の支払い", "This payment")) {
                    DatePicker(guideOSText(language, "支付日期", "支払日", "Payment date"), selection: $paidAt, displayedComponents: .date)
                    TextField(guideOSText(language, "金额", "金額", "Amount"), text: $amount)
                        .keyboardType(.numberPad)
                    TextField(guideOSText(language, "支付方式", "支払い方法", "Payment method"), text: $method)
                    TextField(guideOSText(language, "备注", "メモ", "Notes"), text: $notes, axis: .vertical)
                }
                Section(guideOSText(language, "支付历史", "支払い履歴", "Payment history")) {
                    if payments.isEmpty {
                        Text(guideOSText(language, "还没有支付记录。", "まだ支払い記録がありません。", "No payment records yet."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(payments) { payment in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(GuideOSDate.short(payment.paidAt))
                                        .font(.subheadline.weight(.semibold))
                                    Text(payment.paymentMethod.isEmpty ? guideOSText(language, "未注明方式", "方法未記入", "Method not specified") : payment.paymentMethod)
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
            .navigationTitle(guideOSText(language, "记录已支付", "支払いを記録", "Record payment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(guideOSText(language, "取消", "キャンセル", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? guideOSText(language, "保存中", "保存中", "Saving") : guideOSText(language, "保存", "保存", "Save")) {
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
    @Environment(\.appLanguage) private var language
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
                    TextField(guideOSText(language, "标题", "タイトル", "Title"), text: $title)
                    TextField(guideOSText(language, "公司 / 房东 / 机构", "会社 / 大家 / 機関", "Company / landlord / institution"), text: $provider)
                    TextField(guideOSText(language, "金额（JPY）", "金額（円）", "Amount (JPY)"), text: $amount).keyboardType(.numberPad)
                    TextField(guideOSText(language, "支付方式", "支払い方法", "Payment method"), text: $paymentMethod)
                }
                Section {
                    Stepper(guideOSText(language, "每月 \(dueDay) 号", "毎月\(dueDay)日", "Day \(dueDay) monthly"), value: $dueDay, in: 0...31)
                    Stepper(guideOSText(language, "提前 \(reminderDays) 天提醒", "\(reminderDays)日前に通知", "Remind \(reminderDays)d before"), value: $reminderDays, in: 0...30)
                }
            }
            .navigationTitle(guideOSText(language, "编辑生活事项", "生活項目を編集", "Edit life item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(guideOSText(language, "取消", "キャンセル", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? guideOSText(language, "保存中", "保存中", "Saving") : guideOSText(language, "保存", "保存", "Save")) {
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
