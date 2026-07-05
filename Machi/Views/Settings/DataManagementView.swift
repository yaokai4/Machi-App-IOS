import SwiftUI

/// Settings ▸ 数据管理: shows how much space the app's on-disk caches use
/// (downloaded images/videos, cached page/feed data) and lets the user clear
/// them. All caches are purgeable; clearing just makes the next launch re-fetch
/// from the server. Private chat history lives in the in-memory store (not on
/// disk), so it is never persisted here.
struct DataManagementView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var cache = KaiXCacheManager.shared
    @State private var pending: ClearTarget?

    private enum ClearTarget: String, Identifiable {
        case media, data, localData, all
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .media: return "photo.stack.fill"
            case .data: return "doc.text.fill"
            case .localData: return "bubble.left.and.bubble.right.fill"
            case .all: return "trash.fill"
            }
        }

        var tint: Color {
            switch self {
            case .media: return .cyan
            case .data: return .blue
            case .localData: return .green
            case .all: return .red
            }
        }

        var isDangerous: Bool { self == .localData || self == .all }

        func title(_ T: (String, String, String) -> String) -> String {
            switch self {
            case .media:
                return T("清除图片 / 视频缓存", "画像・動画キャッシュを消去", "Clear images & video")
            case .data:
                return T("清除帖子 / 页面数据缓存", "投稿・ページデータを消去", "Clear posts & page data")
            case .localData:
                return T("清除聊天记录与本地数据", "チャット履歴とローカルデータを消去", "Clear chats & local data")
            case .all:
                return T("清除全部缓存", "すべてのキャッシュを消去", "Clear all cache")
            }
        }

        func detail(_ T: (String, String, String) -> String) -> String {
            switch self {
            case .media:
                return T("释放图片、视频、头像和帖子媒体缓存。", "画像、動画、アバター、投稿メディアのキャッシュを解放します。", "Remove cached photos, videos, avatars, and post media.")
            case .data:
                return T("清空首页、发现页和详情页的本地快照。", "ホーム、発見、詳細ページのローカルスナップショットを消去します。", "Remove local snapshots for feeds, discovery, and detail pages.")
            case .localData:
                return T("重启 App 后清除本机数据库与离线聊天记录。", "App 再起動後、端末内データベースとオフラインチャットを消去します。", "Clear the local database and offline chats after app restart.")
            case .all:
                return T("一次清理所有可重建缓存，并安排本地数据清除。", "再構築可能なキャッシュをすべて消去し、ローカルデータ削除を予約します。", "Clear all rebuildable cache and schedule local data removal.")
            }
        }

        func confirmationTitle(_ T: (String, String, String) -> String) -> String {
            switch self {
            case .media:
                return T("清除媒体缓存?", "メディアキャッシュを消去しますか?", "Clear media cache?")
            case .data:
                return T("清除页面数据缓存?", "ページデータキャッシュを消去しますか?", "Clear page data cache?")
            case .localData:
                return T("清除本地数据?", "ローカルデータを消去しますか?", "Clear local data?")
            case .all:
                return T("清除全部缓存?", "すべてのキャッシュを消去しますか?", "Clear all cache?")
            }
        }

        func confirmationMessage(_ T: (String, String, String) -> String) -> String {
            switch self {
            case .media:
                return T("图片和视频会在下次浏览时重新下载。你的账号、帖子和聊天记录不会受影响。",
                         "画像と動画は次回閲覧時に再ダウンロードされます。アカウント、投稿、チャット履歴には影響しません。",
                         "Images and videos will download again when needed. Your account, posts, and chats are safe.")
            case .data:
                return T("页面快照会在下次打开时重新同步。你的账号、帖子和聊天记录不会受影响。",
                         "ページスナップショットは次回表示時に再同期されます。アカウント、投稿、チャット履歴には影響しません。",
                         "Page snapshots will sync again next time. Your account, posts, and chats are safe.")
            case .localData:
                return T("本机数据库会在重启 App 后清除。服务器上的账号、帖子和聊天记录仍会保留。",
                         "端末内データベースは App 再起動後に消去されます。サーバー上のアカウント、投稿、チャット履歴は残ります。",
                         "The local database will be cleared after app restart. Server-side account, posts, and chats remain.")
            case .all:
                return T("媒体和页面缓存会立即清理，本地数据库会在重启 App 后清除。服务器数据不会丢失。",
                         "メディアとページキャッシュはすぐに消去され、ローカルデータベースは App 再起動後に消去されます。サーバーデータは失われません。",
                         "Media and page cache are cleared now; the local database clears after restart. Server data is safe.")
            }
        }
    }

    fileprivate struct StorageMetric: Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        let bytes: Int64
        let tint: Color
    }

    private func T(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    private var metrics: [StorageMetric] {
        [
            StorageMetric(
                id: "media",
                icon: "photo.stack.fill",
                title: T("图片与视频", "画像と動画", "Images & video"),
                detail: T("帖子媒体、头像、缩略图", "投稿メディア、アバター、サムネイル", "Post media, avatars, thumbnails"),
                bytes: cache.mediaBytes,
                tint: .cyan
            ),
            StorageMetric(
                id: "data",
                icon: "doc.text.fill",
                title: T("页面快照", "ページスナップショット", "Page snapshots"),
                detail: T("首页、发现、详情缓存", "ホーム、発見、詳細キャッシュ", "Home, discovery, detail cache"),
                bytes: cache.dataBytes,
                tint: .blue
            ),
            StorageMetric(
                id: "local",
                icon: "bubble.left.and.bubble.right.fill",
                title: T("本地数据", "ローカルデータ", "Local data"),
                detail: T("会话、聊天记录、资料", "会話、チャット履歴、プロフィール", "Threads, chats, profile data"),
                bytes: cache.dbBytes,
                tint: .green
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                storageHero
                storageBreakdown
                clearActions

                if cache.localDataWipeScheduled {
                    restartNotice
                }

                safetyNote
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.top, KXSpacing.md)
            .kxTabBarSafeBottomPadding(extra: KXSpacing.xl)
        }
        .kxPageBackground()
        .navigationTitle(T("数据管理", "データ管理", "Data & storage"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(cache.isWorking)
                .accessibilityLabel(T("刷新占用", "使用量を更新", "Refresh storage"))
            }
        }
        .task { await cache.refresh() }
        .confirmationDialog(
            pending?.confirmationTitle(T) ?? T("确认清除?", "消去しますか?", "Clear cache?"),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { target in
            Button(target.title(T), role: .destructive) {
                performClear(target)
            }
            Button(T("取消", "キャンセル", "Cancel"), role: .cancel) {}
        } message: { target in
            Text(target.confirmationMessage(T))
        }
    }

    private var storageHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: KXSpacing.lg) {
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    HStack(spacing: KXSpacing.sm) {
                        Image(systemName: cache.isWorking ? "sparkles" : "internaldrive.fill")
                            .font(.caption.weight(.bold))
                        Text(cache.isWorking
                             ? T("正在整理", "整理中", "Cleaning")
                             : T("本机占用", "端末の使用量", "On-device storage"))
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(KXColor.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(KXColor.accentSoft, in: Capsule())

                    Text(KaiXCacheManager.formatted(cache.totalBytes))
                        .kxScaledFont(42, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    Text(T("所有内容都可以从服务器重新同步，清理后应用会更轻盈。",
                           "すべての内容はサーバーから再同期できます。消去後、アプリはより軽くなります。",
                           "Everything can sync again from the server, so cleaning keeps the app light."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ZStack {
                    StorageRingView(metrics: metrics, totalBytes: cache.totalBytes)
                        .frame(width: 98, height: 98)

                    Image(systemName: cache.isWorking ? "arrow.triangle.2.circlepath" : "externaldrive.connected.to.line.below.fill")
                        .kxScaledFont(22, weight: .semibold)
                        .foregroundStyle(KXColor.accent)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(KXColor.glassStroke.opacity(0.65), lineWidth: 0.8))
                }
                .rotationEffect(cache.isWorking ? .degrees(6) : .zero)
                .animation(KXMotion.select, value: cache.isWorking)
                .accessibilityHidden(true)
            }

            HStack(spacing: KXSpacing.sm) {
                metricChip(metrics[0])
                metricChip(metrics[1])
                metricChip(metrics[2])
            }
        }
        .padding(18)
        .premiumPanel(radius: 30, elevated: true)
    }

    private var storageBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: T("缓存占用", "キャッシュ使用量", "Storage used"),
                subtitle: T("按类型查看空间来源", "種類別に容量を確認", "See where the space is going")
            )

            VStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    StorageMetricRow(metric: metric, totalBytes: cache.totalBytes)
                    if index < metrics.count - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .padding(.vertical, KXSpacing.xs)
            .premiumPanel()
        }
    }

    private var clearActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: T("清理空间", "容量を整理", "Clean up"),
                subtitle: T("选择要清理的范围", "消去する範囲を選択", "Choose what to remove")
            )

            VStack(spacing: 10) {
                clearActionButton(.media)
                clearActionButton(.data)
                clearActionButton(.localData)
                clearActionButton(.all)
            }
            .padding(6)
            .premiumPanel()
        }
    }

    private var restartNotice: some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: "restart.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(KXColor.warningSoft, in: Circle())

            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text(T("重启后完成清除", "再起動後に完了", "Finishes after restart"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(T("聊天记录与本地数据已安排清除。完全释放空间需要关闭并重新打开 App。",
                       "チャット履歴とローカルデータの削除を予約しました。完全に解放するには App を閉じて再起動してください。",
                       "Chats and local data are scheduled for removal. Close and reopen the app to fully reclaim space."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(KXColor.warningSoft.opacity(0.65), in: RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 0.8)
        }
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: "checkmark.shield.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(KXColor.accent)
                .frame(width: 28, height: 28)
                .background(KXColor.accentSoft, in: Circle())

            Text(T("清理只移除本机可重建缓存；你的账号、帖子和服务器聊天记录不会丢失。下次打开相关内容时会自动重新加载。",
                   "消去するのは端末内で再構築できるキャッシュのみです。アカウント、投稿、サーバー上のチャット履歴は失われず、次回表示時に自動で再読み込みされます。",
                   "Cleaning removes only rebuildable on-device cache. Your account, posts, and server-side chats remain safe and reload automatically when needed."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, KXSpacing.xs)
        .padding(.top, KXSpacing.xxs)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(title)
                    .font(KXTypography.section)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, KXSpacing.xs)
    }

    @ViewBuilder
    private func metricChip(_ metric: StorageMetric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(metric.tint)
                    .frame(width: 7, height: 7)
                Text(metric.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text(KaiXCacheManager.formatted(metric.bytes))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(KXColor.softBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .stroke(KXColor.separator.opacity(0.42), lineWidth: 0.7)
        }
    }

    @ViewBuilder
    private func clearActionButton(_ target: ClearTarget) -> some View {
        let scheduled = target == .localData && cache.localDataWipeScheduled

        Button {
            pending = target
        } label: {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: target.icon)
                    .kxScaledFont(16, weight: .bold)
                    .foregroundStyle(target.tint)
                    .frame(width: 38, height: 38)
                    .background(target.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(target.title(T))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(target == .all ? Color.red : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(target.detail(T))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                if scheduled {
                    Text(T("已安排", "予約済み", "Scheduled"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, KXSpacing.sm)
                        .frame(height: 24)
                        .background(KXColor.warningSoft, in: Capsule())
                } else if cache.isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                target == .all ? KXColor.dangerSoft.opacity(0.72) : KXColor.softBackground.opacity(0.45),
                in: RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous)
                    .stroke((target == .all ? Color.red.opacity(0.22) : KXColor.separator.opacity(0.48)), lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(cache.isWorking || scheduled)
        .opacity(cache.isWorking || scheduled ? 0.72 : 1)
        .accessibilityLabel(target.title(T))
        .accessibilityHint(target.detail(T))
    }

    private func refresh() async {
        await cache.refresh()
    }

    private func performClear(_ target: ClearTarget) {
        Task {
            withAnimation(KXMotion.select) {
                switch target {
                case .localData:
                    cache.clearLocalData()
                default:
                    break
                }
            }

            switch target {
            case .media:
                await cache.clearMedia()
            case .data:
                await cache.clearData()
            case .localData:
                break
            case .all:
                await cache.clearAll()
            }
        }
    }
}

private struct StorageRingView: View {
    let metrics: [DataManagementView.StorageMetric]
    let totalBytes: Int64

    private var total: Double { max(Double(totalBytes), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(KXColor.softBackground.opacity(0.88), lineWidth: 12)

            ForEach(ringSegments) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(
                        segment.tint.gradient,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private var ringSegments: [RingSegment] {
        var cursor = 0.0
        return metrics.compactMap { metric in
            let value = max(Double(metric.bytes), 0)
            guard value > 0 else { return nil }
            let start = cursor
            let span = min(value / total, 1 - cursor)
            cursor += span
            return RingSegment(id: metric.id, start: start, end: cursor, tint: metric.tint)
        }
    }

    private struct RingSegment: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let tint: Color
    }
}

private struct StorageMetricRow: View {
    let metric: DataManagementView.StorageMetric
    let totalBytes: Int64

    private var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(metric.bytes) / Double(totalBytes), 0), 1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: KXSpacing.md) {
            Image(systemName: metric.icon)
                .kxScaledFont(17, weight: .bold)
                .foregroundStyle(metric.tint)
                .frame(width: 42, height: 42)
                .background(metric.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: KXSpacing.sm) {
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(metric.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text(metric.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: KXSpacing.xxs) {
                        Text(KaiXCacheManager.formatted(metric.bytes))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(percentText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(KXColor.softBackground)
                        Capsule()
                            .fill(metric.tint.gradient)
                            .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 6 : 0))
                    }
                }
                .frame(height: 7)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, KXSpacing.md)
        .accessibilityElement(children: .combine)
    }

    private var percentText: String {
        guard totalBytes > 0 else { return "0%" }
        return "\(Int((fraction * 100).rounded()))%"
    }
}

private extension View {
    func premiumPanel(radius: CGFloat = KXRadius.card, elevated: Bool = false) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(KXColor.cardBackground.opacity(0.78))
            }
            .kxLiquidGlass(.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous), interactive: false)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(KXColor.glassStroke.opacity(0.62), lineWidth: 0.8)
            }
            .shadow(color: KXColor.glassShadow.opacity(elevated ? 0.54 : 0.30), radius: elevated ? 18 : 8, y: elevated ? 8 : 3)
    }
}
