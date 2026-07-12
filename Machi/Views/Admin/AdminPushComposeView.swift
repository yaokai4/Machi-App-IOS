import SwiftUI

/// Admin-only console to compose and send a custom push broadcast to the app.
/// Reachable from Settings only when `currentUser.role == .admin`; the server
/// independently enforces `require_admin` on every endpoint, so this screen just
/// decides what to show — never what's authorized.
struct AdminPushComposeView: View {
    @Environment(\.appLanguage) private var language

    let currentUser: UserEntity

    // Compose state
    @State private var title = ""
    @State private var messageText = ""
    @State private var audience: PushAudience = .all
    @State private var selectedIdsText = ""
    @State private var deepLink: PushDeepLink = .none
    @State private var deepLinkId = ""
    @State private var urgent = false

    // Runtime state
    @State private var previewCount: Int?
    @State private var isPreviewing = false
    @State private var isSending = false
    @State private var banner: Banner?
    @State private var campaigns: [KaiXPushCampaignDTO] = []
    @State private var isLoadingHistory = false

    private enum PushAudience: String, CaseIterable, Hashable {
        case all, active_30d, verified_members, selected
        func title(_ l: AppLanguage) -> String {
            switch self {
            case .all: return at(l, "全部用户", "全ユーザー", "Everyone")
            case .active_30d: return at(l, "活跃30天", "アクティブ30日", "Active 30d")
            case .verified_members: return at(l, "认证会员", "認証会員", "Members")
            case .selected: return at(l, "指定用户", "指定ユーザー", "Selected")
            }
        }
    }

    private enum PushDeepLink: String, CaseIterable, Hashable {
        case none, post, listing
        var apiValue: String { self == .none ? "" : rawValue }
        func title(_ l: AppLanguage) -> String {
            switch self {
            case .none: return at(l, "不跳转", "遷移なし", "No link")
            case .post: return at(l, "打开帖子", "投稿を開く", "Open post")
            case .listing: return at(l, "打开信息", "情報を開く", "Open listing")
            }
        }
    }

    private struct Banner: Identifiable {
        let id = UUID()
        let text: String
        let tint: Color
    }

    private var selectedIds: [String] {
        selectedIdsText
            .replacingOccurrences(of: "，", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !messageText.trimmingCharacters(in: .whitespaces).isEmpty &&
        (audience != .selected || !selectedIds.isEmpty) &&
        (deepLink == .none || !deepLinkId.trimmingCharacters(in: .whitespaces).isEmpty) &&
        !isSending
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                composeCard
                historyCard
            }
            .padding(KXSpacing.screen)
            .padding(.top, KXSpacing.sm)
            .kxTabBarSafeBottomPadding()
            .kxReadableWidth()
        }
        .kxPageBackground()
        .navigationTitle(at(language, "推送广播", "プッシュ配信", "Push broadcast"))
        .overlay(alignment: .top) {
            if let banner {
                KXInlineNotice(message: banner.text, tint: banner.tint) {
                    self.banner = nil
                }
                .padding(.top, 8)
                .padding(.horizontal, KXSpacing.screen)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: banner?.id)
        .task { await loadHistory() }
    }

    // MARK: - compose

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            fieldLabel(at(language, "标题", "タイトル", "Title"))
            TextField(at(language, "例如：系统维护通知", "例：メンテナンスのお知らせ", "e.g. Scheduled maintenance"), text: $title)
                .kxInputField()

            fieldLabel(at(language, "内容", "本文", "Message"))
            TextField(at(language, "推送正文…", "本文…", "Notification body…"), text: $messageText, axis: .vertical)
                .lineLimit(3...6)
                .kxInputField()

            fieldLabel(at(language, "发送对象", "配信対象", "Audience"))
            KXSegmentedControl(PushAudience.allCases, selection: $audience, itemMinWidth: 62, itemHeight: 34) { item in
                Text(item.title(language)).font(.caption.weight(.semibold))
            }
            if audience == .selected {
                TextField(at(language, "用户 ID，逗号分隔", "ユーザーID（カンマ区切り）", "User IDs, comma-separated"), text: $selectedIdsText, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .kxInputField()
            }

            fieldLabel(at(language, "点击跳转", "タップ遷移", "On tap"))
            KXSegmentedControl(PushDeepLink.allCases, selection: $deepLink, itemMinWidth: 74, itemHeight: 34) { item in
                Text(item.title(language)).font(.caption.weight(.semibold))
            }
            if deepLink != .none {
                TextField(at(language, "目标 ID", "対象ID", "Target ID"), text: $deepLinkId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .kxInputField()
            }

            Toggle(isOn: $urgent) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(at(language, "紧急推送", "緊急配信", "Urgent"))
                        .font(.subheadline.weight(.semibold))
                    Text(at(language, "忽略免打扰时段和每日上限，立即触达", "サイレント時間と1日上限を無視して即時配信", "Bypass quiet hours & daily cap"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.red)

            previewRow

            HStack(spacing: KXSpacing.sm) {
                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if isSending {
                            KXSpinner(size: 20, lineWidth: 2.2, tint: .white)
                        } else {
                            Text(at(language, "立即发送", "今すぐ送信", "Send now"))
                        }
                    }
                    .kxGlassButton(enabled: canSend)
                }
                .buttonStyle(KXPressableStyle(scale: 0.98))
                .disabled(!canSend)
            }
        }
        .padding(KXSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.sheet)
    }

    private var previewRow: some View {
        HStack(spacing: KXSpacing.sm) {
            Button {
                Task { await preview() }
            } label: {
                HStack(spacing: 6) {
                    if isPreviewing {
                        KXSpinner(size: 15, lineWidth: 2, tint: KXColor.accent)
                    } else {
                        Image(systemName: "person.3.fill").font(.caption)
                    }
                    Text(at(language, "预览人数", "対象人数", "Preview count"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(KXColor.accent)
                .padding(.horizontal, 12)
                .kxGlassCapsule()
            }
            .buttonStyle(KXPressableStyle(scale: 0.97))
            .disabled(isPreviewing || (audience == .selected && selectedIds.isEmpty))

            if let previewCount {
                Text(at(language, "约 \(previewCount) 人", "約 \(previewCount) 人", "~\(previewCount) users"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - history

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack {
                Text(at(language, "发送记录", "配信履歴", "History"))
                    .font(.headline.weight(.bold))
                Spacer()
                if isLoadingHistory { KXSpinner(size: 16, lineWidth: 2, tint: KXColor.accent) }
            }
            if campaigns.isEmpty && !isLoadingHistory {
                Text(at(language, "还没有发送过推送", "まだ配信はありません", "No broadcasts yet"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(campaigns) { campaign in
                    historyRow(campaign)
                    if campaign.id != campaigns.last?.id { Divider().opacity(0.3) }
                }
            }
        }
        .padding(KXSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.sheet)
    }

    private func historyRow(_ c: KaiXPushCampaignDTO) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(c.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(statusLabel(c.status))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusTint(c.status))
            }
            Text(c.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Text(at(language,
                    "送达 \(c.sentCount)/\(c.recipientCount)\(c.urgent ? " · 紧急" : "")",
                    "配信 \(c.sentCount)/\(c.recipientCount)\(c.urgent ? " · 緊急" : "")",
                    "\(c.sentCount)/\(c.recipientCount) sent\(c.urgent ? " · urgent" : "")"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "sent": return at(language, "已发送", "送信済", "Sent")
        case "sending": return at(language, "发送中", "送信中", "Sending")
        case "partial": return at(language, "部分成功", "一部成功", "Partial")
        case "failed": return at(language, "失败", "失敗", "Failed")
        case "queued": return at(language, "排队中", "待機中", "Queued")
        default: return at(language, "草稿", "下書き", "Draft")
        }
    }

    private func statusTint(_ status: String) -> Color {
        switch status {
        case "sent": return .green
        case "sending", "queued": return .orange
        case "failed": return .red
        case "partial": return .yellow
        default: return .secondary
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    // MARK: - actions

    private func preview() async {
        isPreviewing = true
        defer { isPreviewing = false }
        do {
            previewCount = try await KaiXAPIClient.shared.adminPushCampaignPreview(
                audience: audience.rawValue, userIds: audience == .selected ? selectedIds : [])
        } catch {
            show(error.kaixUserMessage, tint: .orange)
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let campaign = try await KaiXAPIClient.shared.adminCreatePushCampaign(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: messageText.trimmingCharacters(in: .whitespacesAndNewlines),
                audience: audience.rawValue,
                userIds: audience == .selected ? selectedIds : [],
                deepLinkType: deepLink.apiValue,
                deepLinkId: deepLink == .none ? "" : deepLinkId.trimmingCharacters(in: .whitespacesAndNewlines),
                urgent: urgent,
                sendNow: true
            )
            show(at(language, "已开始发送给 \(campaign.recipientCount) 人",
                    "\(campaign.recipientCount) 人へ配信を開始しました",
                    "Sending to \(campaign.recipientCount) users"), tint: .green)
            // Reset the composer for the next broadcast; keep audience choice.
            title = ""; messageText = ""; deepLinkId = ""; deepLink = .none; urgent = false; previewCount = nil
            await loadHistory()
        } catch {
            show(error.kaixUserMessage, tint: .red)
        }
    }

    private func loadHistory() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        campaigns = (try? await KaiXAPIClient.shared.adminPushCampaigns(limit: 30)) ?? campaigns
    }

    private func show(_ text: String, tint: Color) {
        banner = Banner(text: text, tint: tint)
    }
}

/// Trilingual inline copy for the admin-only screen (keeps LocalizationService
/// free of operator-tool strings). Mirrors guideText/settingsText.
private func at(_ l: AppLanguage, _ zh: String, _ ja: String, _ en: String) -> String {
    switch l {
    case .ja: return ja
    case .en: return en
    case .zh, .system: return zh
    }
}
