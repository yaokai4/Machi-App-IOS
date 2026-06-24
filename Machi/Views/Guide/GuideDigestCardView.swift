import Combine
import SwiftUI

/// 本月要点 — the Guide-home digest that unifies bills, contract windows,
/// document expiries, budget alerts and the month's balance into one glance.
/// Self-contained (own loader) so it never entangles the shared GuideViewModel.
@MainActor
final class GuideDigestViewModel: ObservableObject {
    @Published var digest: KaiXGuideDigestDTO?
    @Published var busy = false

    var isLoggedIn: Bool { KaiXBackend.token != nil }

    func load() async {
        guard isLoggedIn else { digest = nil; return }
        digest = try? await KaiXAPIClient.shared.guideDigest()
    }

    func quickSetup(_ profile: String) async {
        busy = true
        defer { busy = false }
        _ = try? await KaiXAPIClient.shared.guideQuickSetup(profile: profile)
        await load()
    }
}

struct GuideDigestCardView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = GuideDigestViewModel()

    let isGuest: Bool

    var body: some View {
        Group {
            if isGuest {
                EmptyView()
            } else if let d = vm.digest {
                if d.hasSetup { digestCard(d) } else { setupCard }
            }
        }
        .task { if !isGuest { await vm.load() } }
    }

    // MARK: 本月要点

    private func digestCard(_ d: KaiXGuideDigestDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(guideOSText(language, "本月要点", "今月の要点", "This month"), systemImage: "sparkles")
                    .font(.headline.weight(.bold))
                Spacer()
                Button(guideOSText(language, "收支详情", "家計簿", "Finance")) { router.open(.guideFinance) }
                    .font(.caption.weight(.bold)).foregroundStyle(KXColor.accent)
            }
            HStack(spacing: 8) {
                digestStat(guideOSText(language, "收入", "収入", "Income"), d.finance.income, tone: .primary)
                digestStat(guideOSText(language, "支出", "支出", "Spent"), d.finance.expense,
                           tone: d.finance.income > 0 && d.finance.expense > d.finance.income ? .red : .primary)
                digestStat(guideOSText(language, "结余", "収支", "Net"), d.finance.net,
                           tone: d.finance.net < 0 ? .red : KXColor.accent)
            }
            let rows = digestRows(d)
            if rows.isEmpty {
                Text(guideOSText(language, "近期没有要扣款的账单、解约窗口或到期证件，继续保持 👍", "近々の支払い・解約期限・証明書の期限はありません 👍", "No upcoming charges, cancellation windows, or expiries. Nice 👍"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KXColor.accentSoft.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 2) {
                    ForEach(rows) { row in
                        Button { router.open(row.route) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: row.icon).font(.subheadline.weight(.bold))
                                    .foregroundStyle(row.tone).frame(width: 22)
                                Text(row.text).font(.subheadline).foregroundStyle(.primary)
                                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(KXColor.separator.opacity(0.8), lineWidth: 0.8))
    }

    private func digestStat(_ label: String, _ value: Int, tone: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(guideMoney(value)).font(.system(size: 15, weight: .black)).foregroundStyle(tone)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(KXColor.accentSoft.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private struct DigestRow: Identifiable {
        let id = UUID()
        let icon: String
        let tone: Color
        let text: String
        let route: KXRoute
    }

    private func digestRows(_ d: KaiXGuideDigestDTO) -> [DigestRow] {
        var rows: [DigestRow] = []
        func dleft(_ n: Int) -> String { n <= 0 ? guideOSText(language, "今天", "今日", "today") : guideOSText(language, "\(n) 天后", "\(n)日後", "in \(n)d") }
        for b in d.upcomingBills.prefix(3) {
            let amt = b.amount > 0 ? " \(guideMoney(b.amount))" : ""
            rows.append(.init(icon: "creditcard.fill", tone: .orange, text: "\(b.title)\(amt) · \(dleft(b.daysLeft))\(guideOSText(language, "扣款", "支払い", " due"))", route: .guideLifePlanner))
        }
        for w in d.contractWindows.prefix(2) {
            let s = w.open ? guideOSText(language, "现在可解约", "解約可能", "can cancel now") : "\(dleft(w.daysLeft))\(guideOSText(language, "进入解约窗口", "解約期間へ", " cancel window"))"
            rows.append(.init(icon: "calendar.badge.clock", tone: KXColor.accent, text: "\(w.title) · \(s)", route: .guideContracts))
        }
        for a in d.budgetAlerts.prefix(2) {
            let s = a.over ? guideOSText(language, "已超预算", "予算超過", "over budget") : guideOSText(language, "接近上限", "上限間近", "near limit")
            rows.append(.init(icon: "chart.pie.fill", tone: a.over ? .red : .orange, text: "\(vm.label(a.category, language)) \(s) · \(guideMoney(a.spent)) / \(guideMoney(a.limit))", route: .guideFinance))
        }
        for doc in d.documentExpiries.prefix(2) {
            let s = doc.daysLeft < 0 ? guideOSText(language, "已过期", "期限切れ", "expired") : "\(dleft(doc.daysLeft))\(guideOSText(language, "到期", "期限", " expires"))"
            rows.append(.init(icon: "person.text.rectangle.fill", tone: doc.daysLeft < 0 ? .red : .cyan, text: "\(doc.title) · \(s)", route: .guideDocuments))
        }
        return Array(rows.prefix(6))
    }

    // MARK: 30s cold start

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(guideOSText(language, "30 秒搭好你的生活管理", "30秒で生活管理をセットアップ", "Set up in 30s"), systemImage: "wand.and.stars")
                .font(.headline.weight(.bold))
            Text(guideOSText(language, "选一个最接近你的身份，先帮你设好一份月度预算模板，记账时自动对照。之后填上真实数字即可。", "近い身分を選ぶと月予算テンプレートを用意します。後で実際の数字を入れてください。", "Pick what fits you and we'll seed a monthly budget template; fill in real numbers later."))
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                setupButton("student", guideOSText(language, "我是学生", "学生です", "Student"))
                setupButton("worker", guideOSText(language, "我在工作", "働いています", "Working"))
                setupButton("general", guideOSText(language, "其他", "その他", "Other"))
            }
        }
        .padding(16)
        .background(KXColor.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(KXColor.accent.opacity(0.3), lineWidth: 1))
    }

    private func setupButton(_ profile: String, _ label: String) -> some View {
        Button {
            Task { await vm.quickSetup(profile) }
        } label: {
            Text(label).font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity).frame(height: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(KXColor.accent)
        .disabled(vm.busy)
    }
}

private extension GuideDigestViewModel {
    func label(_ code: String, _ language: AppLanguage) -> String {
        let map: [String: (String, String, String)] = [
            "rent": ("房租", "家賃", "Rent"), "utilities": ("水电煤", "光熱費", "Utilities"),
            "telecom": ("通信", "通信", "Telecom"), "groceries": ("食材", "食料品", "Groceries"),
            "dining": ("外食", "外食", "Dining"), "transport": ("交通", "交通", "Transport"),
            "entertainment": ("娱乐", "娯楽", "Fun"), "shopping": ("购物", "買い物", "Shopping"),
        ]
        if let t = map[code] { return guideOSText(language, t.0, t.1, t.2) }
        return code
    }
}
