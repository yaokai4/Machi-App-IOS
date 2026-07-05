import SwiftUI

/// 邀请裂变 — "我的邀请" 战绩页.
///
/// Shows the signed-in user's stable invite code, share URL, running counts
/// (invited / qualified / points earned) and the most-recent invitees, plus a
/// system `ShareLink` to spread `https://machicity.com/i/<code>`. Machi Points
/// awarded via referral are virtual scrip (an accounting liability) — never
/// cash and never transferable.
///
/// Data mirrors `GET /api/referral/me` (`server_referral.referral_summary`);
/// the server mints the code lazily on first read, so this page always has a
/// code to show. Guests are gated out at the settings entry, so `require_user`
/// server-side always has a session.
struct MyInvitesView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    private enum LoadState: Equatable {
        case loading
        case loaded(KaiXReferralSummaryDTO)
        case failed(String)
    }

    @State private var state: LoadState = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch state {
                case .loading:
                    LoadingView()
                case .failed(let message):
                    ErrorStateView(message: message) { Task { await load() } }
                case .loaded(let summary):
                    heroCard(summary)
                    statsRow(summary)
                    howItWorksCard(summary)
                    recentSection(summary)
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, KaiXTheme.horizontalPadding)
            .kxTabBarSafeBottomPadding()
        }
        .kxPageBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if case .loading = state { await load() } }
    }

    private var title: String {
        KXListingCopy.pickText(language, "我的邀请", "招待", "Invite friends")
    }

    // MARK: - hero (code + share)

    private func heroCard(_ summary: KaiXReferralSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: "gift.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(KXColor.accentSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text(KXListingCopy.pickText(language, "邀请好友，一起得 Machi 币", "友達を招待して Machi コインを獲得", "Invite friends, both earn Machi Coins"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(inviterRewardLine(summary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // The code itself — big, monospaced, tap-to-copy.
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                Text(KXListingCopy.pickText(language, "我的邀请码", "招待コード", "Your invite code"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Button {
                    UIPasteboard.general.string = summary.code
                    copied = true
                } label: {
                    HStack(spacing: 10) {
                        Text(summary.code)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                            .foregroundStyle(.primary)
                            .kerning(2)
                        Spacer(minLength: 0)
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(copied ? .green : KXColor.accent)
                    }
                    .padding(.horizontal, KXSpacing.lg)
                    .frame(height: 54)
                    .frame(maxWidth: .infinity)
                    .background(KXColor.softBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                            .stroke(KXColor.separator.opacity(0.5), lineWidth: 0.6)
                    }
                }
                .buttonStyle(KXPressableStyle(scale: 0.99, dim: 0.94))
                .accessibilityLabel(KXListingCopy.pickText(language, "复制邀请码", "招待コードをコピー", "Copy invite code"))
            }

            ShareLink(
                item: shareURL(summary),
                subject: Text(KXListingCopy.pickText(language, "来 Machi 一起用吧", "Machi を一緒に使おう", "Join me on Machi")),
                message: Text(shareMessage(summary)),
                preview: SharePreview(KXListingCopy.pickText(language, "Machi 邀请", "Machi 招待", "Machi invite"))
            ) {
                Label(KXListingCopy.pickText(language, "分享邀请链接", "招待リンクを共有", "Share invite link"), systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(KXColor.accent, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            }
            .buttonStyle(KXPressableStyle(scale: 0.99))
        }
        .padding(KXSpacing.lg)
        .kxGlassSurface(radius: KXRadius.lg)
        .animation(.snappy, value: copied)
    }

    // MARK: - stats

    private func statsRow(_ summary: KaiXReferralSummaryDTO) -> some View {
        HStack(spacing: 10) {
            statCell(value: summary.invitedCount,
                     label: KXListingCopy.pickText(language, "已邀请", "招待済み", "Invited"))
            statCell(value: summary.qualifiedCount,
                     label: KXListingCopy.pickText(language, "已合格", "達成", "Qualified"))
            statCell(value: summary.pointsEarned,
                     label: KXListingCopy.pickText(language, "累计得币", "獲得コイン", "Coins earned"),
                     tint: KXColor.accent)
        }
    }

    private func statCell(value: Int, label: String, tint: Color = .primary) -> some View {
        VStack(spacing: KXSpacing.xs) {
            Text(NumberFormatterUtils.compact(value))
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .kxGlassSurface(radius: KXRadius.md)
    }

    // MARK: - how it works

    private func howItWorksCard(_ summary: KaiXReferralSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            Text(KXListingCopy.pickText(language, "怎么得奖励", "特典の受け取り方", "How it works"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            howStep(index: 1, text: KXListingCopy.pickText(language,
                "把邀请链接分享给朋友。",
                "招待リンクを友達に共有します。",
                "Share your invite link with a friend."))
            howStep(index: 2, text: KXListingCopy.pickText(language,
                "朋友用链接注册 Machi。",
                "友達がリンクから Machi に登録します。",
                "Your friend signs up for Machi with the link."))
            howStep(index: 3, text: KXListingCopy.pickText(language,
                "朋友完成首次发帖后，你们双方各得 Machi 币。",
                "友達が最初の投稿をすると、二人ともコインを獲得します。",
                "When they make their first post, you both earn coins."))
            Text(rewardFooter(summary))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, KXSpacing.xxs)
        }
        .padding(KXSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private func howStep(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.accent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(KXColor.accentSoft))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - recent invitees

    @ViewBuilder
    private func recentSection(_ summary: KaiXReferralSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(KXListingCopy.pickText(language, "最近邀请", "最近の招待", "Recent invites"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            if summary.recentInvitees.isEmpty {
                emptyInvitees
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(summary.recentInvitees.enumerated()), id: \.element.id) { pair in
                        inviteeRow(pair.element)
                        if pair.offset < summary.recentInvitees.count - 1 {
                            Divider().overlay(KXColor.separator).padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, KXSpacing.xs)
                .kxGlassSurface(radius: KXRadius.lg)
            }
        }
    }

    private var emptyInvitees: some View {
        VStack(spacing: KXSpacing.sm) {
            Image(systemName: "person.2")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(KXListingCopy.pickText(language,
                "还没有人通过你的链接注册。分享给朋友试试吧！",
                "まだ誰もあなたのリンクから登録していません。友達に共有してみましょう！",
                "No one has signed up with your link yet. Share it with a friend!"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, KXSpacing.lg)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private func inviteeRow(_ invitee: KaiXReferralInviteeDTO) -> some View {
        HStack(spacing: KXSpacing.md) {
            inviteeAvatar(invitee)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(displayName(invitee))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle(invitee))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            statusPill(invitee)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func inviteeAvatar(_ invitee: KaiXReferralInviteeDTO) -> some View {
        ZStack {
            Circle().fill(Color.kaixNamed("blue").gradient)
            Text(avatarInitial(invitee))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let url = invitee.avatarUrl.kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: 120, failureMode: .transparent)
                    .clipShape(Circle())
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private func statusPill(_ invitee: KaiXReferralInviteeDTO) -> some View {
        let (text, tint): (String, Color) = {
            switch invitee.status {
            case "rewarded":
                return (KXListingCopy.pickText(language, "已得币", "獲得済み", "Rewarded"), .green)
            case "qualified":
                return (KXListingCopy.pickText(language, "已合格", "達成", "Qualified"), KXColor.accent)
            case "rejected":
                return (KXListingCopy.pickText(language, "待审核", "確認中", "Under review"), .orange)
            default:
                return (KXListingCopy.pickText(language, "待激活", "登録済み", "Joined"), .secondary)
            }
        }()
        return Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: - copy helpers

    @State private var copied = false

    private func shareURL(_ summary: KaiXReferralSummaryDTO) -> URL {
        // Prefer the server-built shareUrl; fall back to composing it from the
        // code so ShareLink always has a valid URL to hand off.
        URL(string: summary.shareUrl)
            ?? URL(string: "https://machicity.com/i/\(summary.code)")!
    }

    private func shareMessage(_ summary: KaiXReferralSummaryDTO) -> String {
        let link = summary.shareUrl.isEmpty ? "https://machicity.com/i/\(summary.code)" : summary.shareUrl
        return KXListingCopy.pickText(language,
            "我在用 Machi——在日生活助手。用我的邀请链接注册，我们都能拿 Machi 币：\(link)",
            "在日生活の相棒アプリ「Machi」を使っています。私の招待リンクから登録すると、二人ともコインがもらえます：\(link)",
            "I'm using Machi, a life helper for Japan. Sign up with my link and we both get Machi Coins: \(link)")
    }

    private func inviterRewardLine(_ summary: KaiXReferralSummaryDTO) -> String {
        KXListingCopy.pickText(language,
            "好友完成首帖后，你得 \(summary.inviterReward) 币，好友得 \(summary.inviteeReward) 币。",
            "友達が最初の投稿をすると、あなたに \(summary.inviterReward) コイン、友達に \(summary.inviteeReward) コイン。",
            "When your friend makes their first post, you get \(summary.inviterReward) coins and they get \(summary.inviteeReward).")
    }

    private func rewardFooter(_ summary: KaiXReferralSummaryDTO) -> String {
        KXListingCopy.pickText(language,
            "Machi 币是虚拟点数，不可提现或转让。为防刷单，新账号或异常邀请可能需要人工审核。",
            "Machi コインは仮想ポイントで、換金・譲渡はできません。不正防止のため、新規アカウントや異常な招待は確認が入る場合があります。",
            "Machi Coins are virtual points — not cash, not transferable. To prevent abuse, new accounts or unusual invites may be reviewed.")
    }

    private func displayName(_ invitee: KaiXReferralInviteeDTO) -> String {
        let name = invitee.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let handle = invitee.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !handle.isEmpty { return "@\(handle)" }
        return KXListingCopy.pickText(language, "新用户", "新規ユーザー", "New user")
    }

    private func subtitle(_ invitee: KaiXReferralInviteeDTO) -> String {
        let handle = invitee.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? "" : "@\(handle)"
    }

    private func avatarInitial(_ invitee: KaiXReferralInviteeDTO) -> String {
        let source = invitee.displayName.isEmpty ? invitee.handle : invitee.displayName
        return String(source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    // MARK: - load

    private func load() async {
        state = .loading
        do {
            let summary = try await KaiXAPIClient.shared.referralMe()
            state = .loaded(summary)
        } catch {
            state = .failed(error.kaixUserMessage)
        }
    }
}
