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

    private enum ClearTarget: Identifiable {
        case media, data, localData, all
        var id: Int { hashValue }
    }

    private func T(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsSectionCard(title: T("缓存占用", "キャッシュ使用量", "Storage used")) {
                    sizeRow(icon: "internaldrive", tint: .gray,
                            title: T("总占用", "合計", "Total"),
                            bytes: cache.totalBytes, bold: true)
                    SettingsDivider()
                    sizeRow(icon: "photo.on.rectangle", tint: .cyan,
                            title: T("图片 / 视频缓存", "画像・動画キャッシュ", "Images & video"),
                            bytes: cache.mediaBytes)
                    SettingsDivider()
                    sizeRow(icon: "doc.text", tint: .blue,
                            title: T("帖子 / 页面数据缓存", "投稿・ページデータ", "Posts & page data"),
                            bytes: cache.dataBytes)
                    SettingsDivider()
                    sizeRow(icon: "bubble.left.and.bubble.right", tint: .green,
                            title: T("本地数据(含聊天记录)", "ローカルデータ(チャット含む)", "Local data (incl. chats)"),
                            bytes: cache.dbBytes)
                }

                SettingsSectionCard(title: T("清除", "クリア", "Clear")) {
                    actionRow(icon: "photo", tint: .cyan,
                              title: T("清除图片 / 视频缓存", "画像・動画を消去", "Clear images & video")) { pending = .media }
                    SettingsDivider()
                    actionRow(icon: "doc", tint: .blue,
                              title: T("清除帖子 / 页面数据缓存", "投稿・ページデータを消去", "Clear posts & page data")) { pending = .data }
                    SettingsDivider()
                    actionRow(icon: "bubble.left.and.bubble.right", tint: .green,
                              title: T("清除聊天记录与本地数据", "チャット履歴とローカルデータを消去", "Clear chats & local data")) { pending = .localData }
                    SettingsDivider()
                    actionRow(icon: "trash", tint: .red, destructive: true,
                              title: T("清除全部缓存", "すべてのキャッシュを消去", "Clear all cache")) { pending = .all }
                }

                if cache.localDataWipeScheduled {
                    Text(T("聊天记录与本地数据将在重启 App 后清除。",
                           "チャット履歴とローカルデータは App 再起動後に消去されます。",
                           "Chats & local data will be cleared after you restart the app."))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                Text(T("清除后下次打开会重新从服务器加载,不会丢失你的账号或帖子。聊天记录保存在服务器,不会缓存到本机。",
                       "クリア後、次回起動時にサーバーから再読み込みします。アカウントや投稿は失われません。チャット履歴はサーバー側にあり、端末には保存されません。",
                       "After clearing, content reloads from the server on next launch — your account and posts are safe. Chat history lives on the server and is not stored on this device."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                if cache.isWorking {
                    ProgressView().padding(.top, 4)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(T("数据管理", "データ管理", "Data & storage"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await cache.refresh() }
        .confirmationDialog(
            T("确认清除?", "消去しますか?", "Clear cache?"),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { target in
            Button(T("清除", "消去", "Clear"), role: .destructive) {
                Task {
                    switch target {
                    case .media:     await cache.clearMedia()
                    case .data:      await cache.clearData()
                    case .localData: cache.clearLocalData()
                    case .all:       await cache.clearAll()
                    }
                }
            }
            Button(T("取消", "キャンセル", "Cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func sizeRow(icon: String, tint: Color, title: String, bytes: Int64, bold: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 26)
            Text(title).font(bold ? .body.bold() : .body)
            Spacer()
            Text(KaiXCacheManager.formatted(bytes))
                .font(bold ? .body.bold() : .body)
                .foregroundStyle(bold ? .primary : .secondary)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actionRow(icon: String, tint: Color, destructive: Bool = false, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint).frame(width: 26)
                Text(title).foregroundStyle(destructive ? Color.red : Color.primary)
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cache.isWorking)
    }
}
