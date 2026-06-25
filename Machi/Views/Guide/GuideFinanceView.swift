import Combine
import SwiftUI
import UIKit

/// Privacy-first manual finance: log income/expense, see the month's balance,
/// track per-category budgets. No bank links — only what the user types.
@MainActor
final class GuideFinanceViewModel: ObservableObject {
    @Published var summary: KaiXGuideFinanceSummaryDTO?
    @Published var transactions: [KaiXGuideTransactionDTO] = []
    @Published var trend: [KaiXGuideFinanceTrendPoint] = []
    @Published var expenseCats: [KaiXGuideFinanceCategoryDTO] = []
    @Published var incomeCats: [KaiXGuideFinanceCategoryDTO] = []
    @Published var isLoading = false
    @Published var message: String?
    @Published var month: String = GuideFinanceViewModel.currentMonth()
    @Published var currency: String = UserDefaults.standard.string(forKey: "kx-finance-currency") ?? "JPY"

    func setCurrency(_ code: String) {
        currency = code
        UserDefaults.standard.set(code, forKey: "kx-finance-currency")
    }

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
            async let tr = KaiXAPIClient.shared.guideFinanceTrend(months: 6, month: month)
            summary = try await s
            transactions = try await t.items
            trend = (try? await tr.months) ?? []
        } catch {
            message = "加载失败，请稍后重试。"
        }
    }

    func add(kind: String, amount: Int, category: String, date: Date, note: String) async {
        guard amount > 0 else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        do {
            _ = try await KaiXAPIClient.shared.createGuideTransaction(
                .init(kind: kind, amount: amount, category: category, occurredOn: f.string(from: date), note: note.isEmpty ? nil : note, currency: currency)
            )
            await load()
        } catch {
            message = "记账失败，请稍后重试。"
        }
    }

    func postFixed() async {
        do {
            let r = try await KaiXAPIClient.shared.postGuideFixedCosts(month: month)
            await load()
            message = r.posted > 0 ? "已记入 \(r.posted) 笔固定费。" : "本月固定费已全部记过了。"
        } catch {
            message = "操作失败，请稍后重试。"
        }
    }

    func csvExport() -> String {
        var lines = ["date,kind,category,amount,currency,note"]
        for t in transactions {
            let cat = (expenseCats + incomeCats).first { $0.code == t.category }?.zh ?? t.category
            let safeNote = t.note.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "\n", with: " ")
            lines.append("\(t.occurredOn ?? ""),\(t.kind),\(cat),\(t.amount),\(t.currency),\(safeNote)")
        }
        return lines.joined(separator: "\n")
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

let kxFinanceCurrencies: [(code: String, symbol: String, label: String)] = [
    ("JPY", "¥", "日元 JPY"), ("CNY", "CN¥", "人民币 CNY"), ("USD", "$", "美元 USD"),
    ("EUR", "€", "欧元 EUR"), ("KRW", "₩", "韩元 KRW"), ("GBP", "£", "英镑 GBP"),
]

func kxCurrencySymbol(_ code: String) -> String {
    kxFinanceCurrencies.first { $0.code == code }?.symbol ?? "¥"
}

func guideMoney(_ n: Int, currency: String = "JPY") -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return kxCurrencySymbol(currency) + (f.string(from: NSNumber(value: n)) ?? String(n))
}

private struct GuideFinanceShareDoc: Identifiable { let id = UUID(); let url: URL }

private struct GuideFinanceActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
    @State private var shareDoc: GuideFinanceShareDoc?

    private var currentCats: [KaiXGuideFinanceCategoryDTO] {
        kind == "income" ? vm.incomeCats : vm.expenseCats
    }

    private func money(_ n: Int) -> String { guideMoney(n, currency: vm.currency) }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(
                        title: guideOSText(language, "收支与生活成本", "家計簿", "Finance"),
                        subtitle: guideOSText(language, "全部在你的账户里、只有你能看 · 我们不连接银行，只记你手动填的数。", "あなたのアカウント内だけに保存。銀行連携はせず、入力した金額だけを記録します。", "All in your account, visible only to you — no bank links, just what you enter.")
                    )
                    controlsRow
                    summaryCards
                    insightsRow
                    trendChart
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
        .sheet(item: $shareDoc) { doc in GuideFinanceActivityView(url: doc.url) }
    }

    // MARK: Controls (currency · 记入固定费 · 导出)

    private var controlsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(kxFinanceCurrencies, id: \.code) { c in
                        Button(c.label) { vm.setCurrency(c.code) }
                    }
                } label: {
                    chipLabel(icon: "yensign.circle", text: vm.currency)
                }
                Button {
                    Task { await vm.postFixed() }
                } label: {
                    chipLabel(icon: "arrow.triangle.2.circlepath", text: guideOSText(language, "记入本月固定费", "今月の固定費を記録", "Post fixed costs"))
                }
                Button {
                    if let url = writeCsvTempFile() { shareDoc = GuideFinanceShareDoc(url: url) }
                } label: {
                    chipLabel(icon: "square.and.arrow.up", text: guideOSText(language, "导出 CSV", "CSV書き出し", "Export CSV"))
                }
            }
        }
    }

    private func chipLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption.weight(.bold)).foregroundStyle(KXColor.accent)
            Text(text).font(.caption.weight(.bold)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(KXColor.livingSurface.opacity(0.76), in: Capsule())
        .overlay(Capsule().stroke(KXColor.separator.opacity(0.8), lineWidth: 0.8))
    }

    private func writeCsvTempFile() -> URL? {
        let csv = "\u{FEFF}" + vm.csvExport()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("machi-finance-\(vm.month).csv")
        do { try csv.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    // MARK: Insights

    @ViewBuilder private var insightsRow: some View {
        if let s = vm.summary, s.income > 0 || !s.byCategory.isEmpty {
            let savingsRate = s.income > 0 ? Int((Double(s.net) / Double(s.income) * 100).rounded()) : 0
            let fixedShare = s.income > 0 ? Int((Double(s.fixedMonthly) / Double(s.income) * 100).rounded()) : 0
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.caption.weight(.bold)).foregroundStyle(KXColor.accent)
                if s.income > 0 {
                    Text(guideOSText(language, "储蓄率 ", "貯蓄率 ", "Savings ")).font(.caption.weight(.semibold))
                        + Text("\(savingsRate)%").font(.caption.weight(.bold)).foregroundColor(savingsRate >= 0 ? KXColor.accent : .red)
                }
                if s.income > 0 && s.fixedMonthly > 0 {
                    Text(guideOSText(language, "· 固定费占收入 \(fixedShare)%", "· 固定費\(fixedShare)%", "· Fixed \(fixedShare)%"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let top = s.byCategory.first {
                    Text(guideOSText(language, "· 最大支出 \(vm.label(language, code: top.category))", "· 最大 \(vm.label(language, code: top.category))", "· Top \(vm.label(language, code: top.category))"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(KXColor.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Trend

    @ViewBuilder private var trendChart: some View {
        if vm.trend.count > 1 {
            let maxV = max(1, vm.trend.flatMap { [$0.income, $0.expense] }.max() ?? 1)
            VStack(alignment: .leading, spacing: 12) {
                Text(guideOSText(language, "近 6 个月趋势", "直近6か月の推移", "Last 6 months"))
                    .font(.headline.weight(.bold))
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(vm.trend) { m in
                        VStack(spacing: 5) {
                            HStack(alignment: .bottom, spacing: 2) {
                                Capsule().fill(KXColor.accent.opacity(0.85))
                                    .frame(width: 9, height: max(3, CGFloat(m.income) / CGFloat(maxV) * 88))
                                Capsule().fill(Color.red.opacity(0.7))
                                    .frame(width: 9, height: max(3, CGFloat(m.expense) / CGFloat(maxV) * 88))
                            }
                            .frame(height: 88, alignment: .bottom)
                            Text(String(m.month.suffix(2)) + guideOSText(language, "月", "月", ""))
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 14) {
                    legendDot(color: KXColor.accent.opacity(0.85), text: guideOSText(language, "收入", "収入", "Income"))
                    legendDot(color: Color.red.opacity(0.7), text: guideOSText(language, "支出", "支出", "Spent"))
                }
            }
            .padding(16)
            .background(KXColor.livingSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8))
        }
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    // MARK: Dashboard

    private var summaryCards: some View {
        let s = vm.summary
        let trend = (s?.expense ?? 0) - (s?.lastMonthExpense ?? 0)
        return HStack(spacing: 10) {
            GuideFinanceStat(
                label: guideOSText(language, "本月收入", "今月の収入", "Income"),
                value: money(s?.income ?? 0), positive: true, icon: "arrow.up.right",
                sub: nil
            )
            GuideFinanceStat(
                label: guideOSText(language, "本月支出", "今月の支出", "Spent"),
                value: money(s?.expense ?? 0), positive: false, icon: "arrow.down.right",
                sub: trend != 0 ? guideOSText(language, "较上月\(trend > 0 ? "多" : "少") \(money(abs(trend)))", "前月比\(trend > 0 ? "+" : "-")\(money(abs(trend)))", "\(trend > 0 ? "+" : "-")\(money(abs(trend))) vs last") : nil
            )
            GuideFinanceStat(
                label: guideOSText(language, "本月结余", "今月の収支", "Balance"),
                value: money(s?.net ?? 0), positive: (s?.net ?? 0) >= 0, icon: "equal",
                sub: (s?.fixedMonthly ?? 0) > 0 ? guideOSText(language, "固定支出约 \(money(s?.fixedMonthly ?? 0))/月", "固定費 約\(money(s?.fixedMonthly ?? 0))/月", "Fixed ~\(money(s?.fixedMonthly ?? 0))/mo") : nil
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
                .background(KXColor.livingSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
        .background(KXColor.livingSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8))
    }

    // MARK: Category bars

    @ViewBuilder private var categoryBars: some View {
        if let s = vm.summary, !s.byCategory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(guideOSText(language, "本月分类支出", "今月のカテゴリ別支出", "By category"))
                    .font(.headline.weight(.bold))
                GuideCategoryDonut(segments: s.byCategory, total: s.expense, money: money) { vm.label(language, code: $0) }
                ForEach(s.byCategory, id: \.category) { c in
                    let budget = s.budgets.first { $0.category == c.category }
                    let limit = budget?.limit ?? 0
                    let over = limit > 0 && c.amount > limit
                    let pct = limit > 0 ? min(1.0, Double(c.amount) / Double(limit)) : 0
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(vm.label(language, code: c.category)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(limit > 0 ? "\(money(c.amount)) / \(money(limit))" : money(c.amount))
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
                    .background(KXColor.livingSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .background(KXColor.livingSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(KXColor.livingSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    Text((t.isIncome ? "+" : "-") + money(t.amount))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(t.isIncome ? KXColor.accent : Color.primary)
                }
                .padding(12)
                .background(KXColor.livingSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { Task { await vm.delete(t) } } label: {
                        Label(guideOSText(language, "删除", "削除", "Delete"), systemImage: "trash")
                    }
                }
            }
        }
    }
}

private let kxCategoryColors: [Color] = [
    Color(red: 0.08, green: 0.44, blue: 0.40), Color(red: 0.91, green: 0.54, blue: 0.23),
    Color(red: 0.36, green: 0.56, blue: 0.94), Color(red: 0.85, green: 0.33, blue: 0.31),
    Color(red: 0.61, green: 0.35, blue: 0.71), Color(red: 0.23, green: 0.63, blue: 0.49),
    Color(red: 0.88, green: 0.69, blue: 0.13), Color(red: 0.48, green: 0.54, blue: 0.63),
]

private struct GuideCategoryDonut: View {
    let segments: [KaiXGuideFinanceSummaryDTO.CategoryAmount]
    let total: Int
    let money: (Int) -> String
    let label: (String) -> String

    private var capped: [(label: String, amount: Int, color: Color)] {
        guard total > 0 else { return [] }
        let top = Array(segments.prefix(8))
        var out: [(String, Int, Color)] = []
        for (i, s) in top.enumerated() { out.append((label(s.category), s.amount, kxCategoryColors[i % kxCategoryColors.count])) }
        let rest = segments.dropFirst(8).reduce(0) { $0 + $1.amount }
        if rest > 0 { out.append(("其他", rest, Color.gray.opacity(0.5))) }
        return out
    }

    var body: some View {
        if total > 0 {
            HStack(spacing: 16) {
                ZStack {
                    ForEach(Array(donutStops().enumerated()), id: \.offset) { _, seg in
                        Circle()
                            .trim(from: seg.from, to: seg.to)
                            .stroke(seg.color, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 1) {
                        Text(guideMoney(total, currency: "JPY")).font(.system(size: 13, weight: .black)).minimumScaleFactor(0.5).lineLimit(1)
                        Text("本月支出").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(capped.enumerated()), id: \.offset) { _, seg in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(seg.color).frame(width: 9, height: 9)
                            Text(seg.label).font(.caption2.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Int((Double(seg.amount) / Double(total) * 100).rounded()))%").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.livingSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KXColor.separator.opacity(0.7), lineWidth: 0.7))
        }
    }

    private func donutStops() -> [(from: CGFloat, to: CGFloat, color: Color)] {
        var acc = 0.0
        var out: [(CGFloat, CGFloat, Color)] = []
        for seg in capped {
            let from = acc / Double(total)
            acc += Double(seg.amount)
            out.append((CGFloat(from), CGFloat(acc / Double(total)), seg.color))
        }
        return out
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
        .background(KXColor.livingSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(KXColor.separator.opacity(0.7), lineWidth: 0.7))
    }
}
