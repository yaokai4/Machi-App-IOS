import SwiftUI

/// Compact in-progress goal card shown on the Guide home (今日) dashboard.
///
/// It is rendered ONLY when there is a real, unfinished plan (<100%) — the
/// dashboard gates on `plan.progressPercent < 100` — so a finished or absent
/// plan never takes the hero slot. There is a single "继续" action that opens
/// the full task list; reminders moved to 管理 → 个人提醒设置, so this card no
/// longer competes with the dashboard's own "全部待办" link.
struct GuideOSPlanCard: View {
    @Environment(\.appLanguage) private var language
    let plan: KaiXGuidePlanDTO?
    let isGuest: Bool
    let isLoading: Bool
    let onOpenPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().stroke(KXColor.accentSoft, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: CGFloat((plan?.progressPercent ?? 0)) / 100)
                        .stroke(KXColor.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(plan?.progressPercent ?? 0)%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan?.title ?? guideOSText(language, "进行中的目标", "進行中の目標", "Active goal"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(plan?.nextTodo?.title ?? guideOSText(language, "继续推进下一步。", "次の一歩を進めましょう。", "Keep going with the next step."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button(action: isGuest ? { GuestGate.shared.requireLogin("登录后可以生成和同步 Guide 计划。") } : onOpenPlan) {
                Text(isLoading ? guideOSText(language, "同步中", "同期中", "Syncing") : guideOSText(language, "继续这个目标", "この目標を続ける", "Continue goal"))
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(.fullArea)
            .contentShape(Rectangle())
            .foregroundStyle(.white)
            .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(15)
        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
