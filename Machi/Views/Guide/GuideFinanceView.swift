import Combine
import SwiftUI

/// Privacy-first manual finance: log income/expense, see the month's balance,
/// track per-category budgets. No bank links — only what the user types.
@MainActor
final class GuideFinanceViewModel: ObservableObject {
    @Published var summary: KaiXGuideFinanceSummaryDTO?
    @Published var transactions: [KaiXGuideTransactionDTO] = []
    @Published var expenseCats: [KaiXGuideFinanceCategoryDTO] = []
    @Published var incomeCats: [KaiXGuideFinanceCategoryDTO] = []
    @Published var isLoading = false
    @Published var message: String?
    @Published var month: String = GuideFinanceViewModel.currentMonth()

    var isLoggedIn: Bool { KaiXBackend.token != nil }

    static func currentMonth() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    func requireLogin() -> Bool {
        guard isLoggedIn else {
            GuestGate.shared.requireLogin("登录后可以记账、查看本月收支和预算。")
            return false
        }
        return true
    }

    func loadCategories() async {
        guard isLoggedIn, expenseCats.isEmpty else { return }
        if let resp = try? await KaiXAPIClient.shared.guideFinanceCategories() {
            expenseCats = resp.expense
            incomeCats = resp.income
        }
    }

    func load() async {
        guard isLoggedIn else { summary = nil; transactions = []; return }
        isLoading = true
        defer { isLoading = false }
        await loadCategories()
        do {
            async let s = KaiXAPIClient.shared.guideFinanceSummary(month: month)
            async let t = KaiXAPIClient.shared.guideTransactions(month: month)
            summary = try await s
            transactions = try await t.items
        } catch {
            message = "加载失败，请稍后重试。"
        }
    }

    func add(kind: String, amount: Int, category: String, date: Date, note: String) async {
        guard amount > 0 else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        do {
            _ = try await KaiXAPIClient.shared.createGuideTransaction(
                .init(kind: kind, amount: amount, category: category, occurredOn: f.string(from: date), note: note.isEmpty ? nil : note)
            )
            await load()
        } catch {
            message = "记账失败，请稍后重试。"
        }
    }

    func delete(_ tx: KaiXGuideTransactionDTO) async {
        transactions.removeAll { $0.id == tx.id }
        try? await KaiXAPIClient.shared.deleteGuideTransaction(id: tx.id)
        await load()
    }

    func setBudget(category: String, limit: Int) async {
        do {
            _ = try await KaiXAPIClient.shared.setGuideBudget(category: category, monthlyLimit: limit)
            await load()
            message = limit > 0 ? "预算已更新。" : "预算已取消。"
        } catch {
            message = "预算保存失败，请稍后重试。"
        }
    }

    func label(_ language: AppLanguage, code: String) -> String {
        if let c = (expenseCats + incomeCats).first(where: { $0.code == code }) {
            return guideOSText(language, c.zh, c.ja, c.en)
        }
        return code
    }
}

func guideYen(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return "¥" + (f.string(from: NSNumber(value: n)) ?? String(n))
}

struct GuideFinanceView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var vm = GuideFinanceViewModel()

    @State private var kind = "expense"
    @State private var amountText = ""
    @State private var category = "rent"
    @State private var occurredOn = Date()
    @State private var note = ""
    @State private var budgetCategory = "rent"
    @State private var budgetLimitText = ""

    private var currentCats: [KaiXGuideFinanceCategoryDTO] {
        kind == "income" ? vm.incomeCats : vm.expenseCats
    }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(
                        title: guideOSText(language, "收支与生活成本", "家計簿", "Finance"),
                        subtitle: guideOSText(language, "全部在你的账户里、只有你能看 · 我们不连接银行，只记你手动填的数。", "あなたのアカウント内だけに保存。銀行連携はせず、入力した金額だけを記録します。", "All in your account, visible only to you — no bank links, just what you enter.")
                    )
                    summaryCards
                    quickAdd
                    if let message = vm.message { GuideOSNotice(message: message) }
                    categoryBars
                    budgetEditor
                    ledger
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "收支记账", "家計簿", "Finance"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm.requireLogin() { await vm.load() }
        }
        .refreshable { await vm.load() }
    }

    // MARK: Dashboard

    private var summaryCards: some View {
        let s = vm.summary
        let trend = (s?.expense ?? 0) - (s?.lastMonthExpense ?? 0)
        return HStack(spacing: 10) {
            GuideFinanceStat(
                label: guideOSText(language, "本月收入", "今月の収入", "Income"),
                value: guideYen(s?.income ?? 0), positive: true, icon: "arrow.up.right",
                sub: nil
            )
            GuideFinanceStat(
                label: guideOSText(language, "本月支出", "今月の支出", "Spent"),
                value: guideYen(s?.expense ?? 0), positive: false, icon: "arrow.down.right",
                sub: trend != 0 ? guideOSText(language, "较上月\(trend > 0 ? "多" : "少") \(guideYen(abs(trend)))", "前月比\(trend > 0 ? "+" : "-")\(guideYen(abs(trend)))", "\(trend > 0 ? "+" : "-")\(guideYen(abs(trend))) vs last") : nil
            )
            GuideFinanceStat(
                label: guideOSText(language, "本月结余", "今月の収支", "Balance"),
                value: guideYen(s?.net ?? 0), positive: (s?.net ?? 0) >= 0, icon: "equal",
                sub: (s?.fixedMonthly ?? 0) > 0 ? guideOSText(language, "固定支出约 \(guideYen(s?.fixedMonthly ?? 0))/月", "固定費 約\(guideYen(s?.fixedMonthly ?? 0))/月", "Fixed ~\(guideYen(s?.fixedMonthly ?? 0))/mo") : nil
            )
        }
    }

    // MARK: Quick add

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(guideOSText(language, "记一笔", "記録する", "Add"))
                .font(.headline.weight(.bold))
            Picker("", selection: $kind) {
                Text(guideOSText(language, "支出", "支出", "Expense")).tag("expense")
                Text(guideOSText(language, "收入", "収入", "Income")).tag("income")
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, newValue in
                category = newValue == "income" ? "salary" : "rent"
            }
            HStack(spacing: 8) {
                Text("¥").font(.title2.weight(.black)).foregroundStyle(.secondary)
                TextField("0", text: $amountText)
                    .keyboardType(.numberPad)
                    .font(.title.weight(.black))
                    .onChange(of: amountText) { _, v in
                        let digits = v.filter { $0.isNumber }
                        if digits != v { amountText = digits }
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(KXColor.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Picker(guideOSText(language, "分类", "カテゴリ", "Category"), selection: $category) {
                ForEach(currentCats) { c in
                    Text(guideOSText(language, c.zh, c.ja, c.en)).tag(c.code)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            GuideOSDateField(title: guideOSText(language, "日期", "日付", "Date"), date: $occurredOn)
            TextField(guideOSText(language, "备注（可选）", "メモ（任意）", "Note (optional)"), text: $note)
                .padding(.horizontal, 12).frame(height: 40)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                let amount = Int(amountText) ?? 0
                Task {
                    await vm.add(kind: kind, amount: amount, category: category, date: occurredOn, note: note)
                    amountText = ""; note = ""
                }
            } label: {
                Label(guideOSText(language, "记一笔", "記録する", "Add"), systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity).frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(KXColor.accent)
            .disabled((Int(amountText) ?? 0) <= 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8))
    }

    // MARK: Category bars

    @ViewBuilder private var categoryBars: some View {
        if let s = vm.summary, !s.byCategory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(guideOSText(language, "本月分类支出", "今月のカテゴリ別支出", "By category"))
                    .font(.headline.weight(.bold))
                ForEach(s.byCategory, id: \.category) { c in
                    let budget = s.budgets.first { $0.category == c.category }
                    let limit = budget?.limit ?? 0
                    let over = limit > 0 && c.amount > limit
                    let pct = limit > 0 ? min(1.0, Double(c.amount) / Double(limit)) : 0
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(vm.label(language, code: c.category)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(limit > 0 ? "\(guideYen(c.amount)) / \(guideYen(limit))" : guideYen(c.amount))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(over ? Color.red : Color.primary)
                        }
                        if limit > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.18))
                                    Capsule().fill(over ? Color.red : KXColor.accent)
                                        .frame(width: max(4, geo.size.width * pct))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    // MARK: Budget editor

    private var budgetEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(guideOSText(language, "分类预算", "カテゴリ予算", "Budgets"))
                .font(.headline.weight(.bold))
            Picker(guideOSText(language, "分类", "カテゴリ", "Category"), selection: $budgetCategory) {
                ForEach(vm.expenseCats) { c in
                    Text(guideOSText(language, c.zh, c.ja, c.en)).tag(c.code)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text("¥").font(.headline.weight(.bold)).foregroundStyle(.secondary)
                TextField(guideOSText(language, "每月上限（0=取消）", "上限（0で解除）", "Monthly limit (0 = off)"), text: $budgetLimitText)
                    .keyboardType(.numberPad)
                    .onChange(of: budgetLimitText) { _, v in
                        let digits = v.filter { $0.isNumber }
                        if digits != v { budgetLimitText = digits }
                    }
                Button(guideOSText(language, "保存", "保存", "Save")) {
                    Task { await vm.setBudget(category: budgetCategory, limit: Int(budgetLimitText) ?? 0); budgetLimitText = "" }
                }
                .buttonStyle(.bordered)
                .tint(KXColor.accent)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8))
    }

    // MARK: Ledger

    @ViewBuilder private var ledger: some View {
        Text(guideOSText(language, "本月明细", "今月の明細", "This month"))
            .font(.headline.weight(.bold))
        if vm.transactions.isEmpty && !vm.isLoading {
            GuideOSEmptyPanel(
                title: guideOSText(language, "本月还没有记录", "今月の記録はまだありません", "Nothing logged yet"),
                subtitle: guideOSText(language, "用上方「记一笔」记下第一笔收入或支出，概览会自动汇总。", "上の「記録する」から最初の収支を入力すると、概要が自動集計されます。", "Add your first entry above and the dashboard updates automatically.")
            )
        } else {
            ForEach(vm.transactions) { t in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.label(language, code: t.category) + (t.note.isEmpty ? "" : " · \(t.note)"))
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(t.occurredOn ?? "").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text((t.isIncome ? "+" : "-") + guideYen(t.amount))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(t.isIncome ? KXColor.accent : Color.primary)
                }
                .padding(12)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { Task { await vm.delete(t) } } label: {
                        Label(guideOSText(language, "删除", "削除", "Delete"), systemImage: "trash")
                    }
                }
            }
        }
    }
}

private struct GuideFinanceStat: View {
    let label: String
    let value: String
    let positive: Bool
    let icon: String
    let sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2.weight(.bold))
                    .foregroundStyle(positive ? KXColor.accent : Color.red)
                Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 17, weight: .black)).minimumScaleFactor(0.6).lineLimit(1)
            if let sub { Text(sub).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(KXColor.separator.opacity(0.7), lineWidth: 0.7))
    }
}
