import SwiftUI

/// 房间内部 —— 进来就像进了游戏房间:顶部是局的信息(什么局/时间/位置/
/// 还差几人),中间一排「在房间里的人」,下面是房间聊天;没加入也能围观,
/// 想说话先点「加入这个局」。
struct SocialRoomDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState

    let roomId: String
    let currentUser: UserEntity

    @State private var room: KaiXRoomDTO?
    @State private var messages: [KaiXRoomMessageDTO] = []
    @State private var nextBefore: String?
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var isJoining = false
    @State private var isClosing = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    /// 操作结果弹窗的标题(具体动作名,如「发送失败」);nil 时回落到通用「提示」。
    @State private var actionTitle: String?
    @State private var showLeaveConfirm = false
    /// 房主「已成团,关闭报名」的确认弹窗。
    @State private var showCloseConfirm = false
    /// 待确认拉黑的消息作者(长按消息 → 拉黑用户)。
    @State private var blockTarget: KaiXUserDTO?
    /// 本地黑名单镜像(与 ChatView / ProfileView / 设置▸黑名单共用同一事实源):
    /// 拉黑立即在本地过滤其房间消息,不等服务端下一次轮询。
    @AppStorage private var blockedUserIdsRaw: String
    /// 进房后本地已确认看过、但尚未反映进 room.message_count 快照的新消息数
    /// (自己刚发的 + 轮询刚拉到的):离开房间时把已读水位补齐到快照 + 该差值,
    /// 否则刚发完就退出会在列表上给自己挂一个假未读角标。
    @State private var seenSinceRoomSnapshot = 0
    /// 局信息默认收起——聊天优先。点顶部信息条展开(描述/时间/位置/成员)。
    @State private var showInfo = false
    /// 轻量轮询:房间聊天没有专用推送通道,前台每 8s 刷一次新消息。
    @State private var pollTask: Task<Void, Never>?
    /// 用户是否贴近聊天底部(底部哨兵可见即视为贴底)。轮询到的新消息只在贴底时
    /// 自动跟随滚动;用户翻阅历史时绝不把阅读位置拽回底部。
    @State private var isNearBottom = true
    /// 自己发送成功后强制滚底(即使此前翻在历史里,也要看到自己的消息)。
    @State private var forceScrollToBottomTick = 0
    /// room 覆写代际:join/leave 落地时 +1;轮询发起前捕获、落地前比对,防止
    /// mutation 前发出的过期 GET 快照把 viewer_joined 回滚(输入栏闪回加入按钮)。
    @State private var roomMutationGeneration = 0

    init(roomId: String, currentUser: UserEntity) {
        self.roomId = roomId
        self.currentUser = currentUser
        KXBlocklist.migrateLegacyIfNeeded(to: currentUser.id)
        _blockedUserIdsRaw = AppStorage(wrappedValue: "", KXBlocklist.storageKey(for: currentUser.id))
    }

    private var tint: Color { KXRoomStyle.tint(room?.typeKey ?? "chat") }
    private var joined: Bool { room?.joined ?? false }
    private var isHost: Bool { room?.isHostViewer ?? false }

    private var blockedUserIds: Set<String> {
        Set(blockedUserIdsRaw.split(separator: "|").map(String.init))
    }

    /// 拉黑用户的消息本地即时隐藏(系统消息不过滤)。服务端轮询仍会带回它们,
    /// 每次渲染时按黑名单过滤即可,无需改动查重/分页逻辑。
    private var visibleMessages: [KaiXRoomMessageDTO] {
        guard !blockedUserIds.isEmpty else { return messages }
        return messages.filter { $0.isSystem || !blockedUserIds.contains($0.user?.id ?? "") }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isLoading {
                LoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, room == nil {
                ErrorStateView(message: errorMessage) { Task { await load() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let room {
                content(room)
            }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .kxHidesTabBar(reason: .custom("room-chat"))
        .task(id: roomId) { await load() }
        .onDisappear {
            pollTask?.cancel()
            // 离开即视为读完:快照计数 + 快照后本地已见的增量(自己刚发的/刚轮询到
            // 的),否则刚发完消息就退出会给自己挂假未读角标。markRead 单调,不怕
            // 过期快照把水位拉低。
            if let count = room?.message_count {
                KXRoomReadMarks.markRead(userId: currentUser.id, roomId: roomId, messageCount: count + seenSinceRoomSnapshot)
            }
        }
        .confirmationDialog(
            isHost
                ? KXListingCopy.pickText(language, "解散这个局?", "ルームを解散しますか?", "Disband this room?")
                : KXListingCopy.pickText(language, "退出这个局?", "ルームを退出しますか?", "Leave this room?"),
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button(
                isHost
                    ? KXListingCopy.pickText(language, "解散房间", "解散する", "Disband")
                    : KXListingCopy.pickText(language, "退出", "退出する", "Leave"),
                role: .destructive
            ) {
                Task { await leave() }
            }
            Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            KXListingCopy.pickText(language, "已成团,关闭报名?", "メンバー決定として締め切りますか?", "Close signups?"),
            isPresented: $showCloseConfirm,
            titleVisibility: .visible
        ) {
            Button(KXListingCopy.pickText(language, "关闭报名", "締め切る", "Close signups")) {
                Task { await closeRoom() }
            }
            Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(KXListingCopy.pickText(language, "关闭后新人无法再加入,已加入的成员不受影响。", "締め切ると新しい参加はできなくなります。参加中のメンバーはそのままです。", "New people can't join after this. Current members stay."))
        }
        .confirmationDialog(
            KXListingCopy.pickText(language, "拉黑这个用户?", "このユーザーをブロックしますか?", "Block this user?"),
            isPresented: Binding(
                get: { blockTarget != nil },
                set: { if !$0 { blockTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: blockTarget
        ) { target in
            Button(L("blockUser", language), role: .destructive) {
                Task { await block(target) }
            }
            Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
        } message: { _ in
            Text(KXListingCopy.pickText(language, "拉黑后将不再看到 TA 的消息,TA 也无法私信你。", "ブロックすると相手のメッセージは表示されず、DMも届きません。", "You won't see their messages and they can't DM you."))
        }
        .alert(actionTitle ?? KXListingCopy.pickText(language, "提示", "お知らせ", "Notice"), isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil; actionTitle = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: KXSpacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KXListingCopy.pickText(language, "返回", "戻る", "Back"))
            VStack(alignment: .leading, spacing: 2) {
                Text(room?.title ?? KXListingCopy.pickText(language, "房间", "ルーム", "Room"))
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                if let room {
                    Text("\(KXRoomStyle.label(room.typeKey, fallback: room.room_type_label, language)) · \(KXListingCopy.pickText(language, "\(room.memberCountValue) 人在房间里", "\(room.memberCountValue)人が参加中", "\(room.memberCountValue) inside"))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let room {
                ShareLink(item: KaiXBackend.marketingSiteURL.appendingPathComponent("rooms/\(room.id)"),
                          subject: Text(room.title)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .kxGlassCircle()
                }
                .accessibilityLabel(KXListingCopy.pickText(language, "分享", "共有", "Share"))
            }
            if let room {
                Menu {
                    if isHost {
                        if room.isOpen {
                            Button {
                                showCloseConfirm = true
                            } label: {
                                Label(KXListingCopy.pickText(language, "已成团,关闭报名", "メンバー決定(締め切る)", "Close signups"), systemImage: "checkmark.seal")
                            }
                            .disabled(isClosing)
                        }
                        Button(role: .destructive) {
                            showLeaveConfirm = true
                        } label: {
                            Label(KXListingCopy.pickText(language, "解散房间", "ルームを解散", "Disband room"), systemImage: "trash")
                        }
                    } else if joined {
                        Button(role: .destructive) {
                            showLeaveConfirm = true
                        } label: {
                            Label(KXListingCopy.pickText(language, "退出这个局", "ルームを退出", "Leave room"), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    // Apple Guideline 1.2:UGC 聊天房必须有可发现的举报入口,围观者
                    // (未加入)也要能举报,所以菜单不再只在 joined 时出现。
                    if !isHost, room.host_user_id?.isEmpty == false {
                        Button(role: .destructive) {
                            reportRoom(room)
                        } label: {
                            Label(KXListingCopy.pickText(language, "举报房间", "ルームを通報", "Report room"), systemImage: "flag")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .kxGlassCircle()
                }
                // 与 EventDetailView 的省略号按钮一致:旁白只能念出符号名,须给三语标签。
                .accessibilityLabel(KXListingCopy.pickText(language, "更多", "その他", "More"))
            }
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.sm)
        .kxGlassBar(ignoresTopSafeArea: true)
    }

    /// 聊天 App 式布局:可折叠的局信息条 + 定高内部滚动的消息区 + 底部固定操作。
    /// 关键是消息区用 `.frame(maxHeight: .infinity)` 吃掉剩余空间自己滚,不会把
    /// 整页越撑越长(之前的 bug)。
    private func content(_ room: KaiXRoomDTO) -> some View {
        VStack(spacing: 0) {
            heroCover(room)
            roomInfoDisclosure(room)
            chatScroll(room)
            bottomBar(room)
        }
    }

    /// 房间封面 hero:设了封面才铺一条定高(200pt)横幅,加载/失败时露出类型渐变
    /// 兜底;没有封面的局保持原样(聊天优先、不占高),下面定高聊天区布局不受影响。
    @ViewBuilder
    private func heroCover(_ room: KaiXRoomDTO) -> some View {
        if let url = room.coverFullURL {
            ZStack {
                LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: KXRoomStyle.icon(room.typeKey))
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(KXColor.onTint(tint).opacity(0.85))
                    }
                CachedMediaImageView(url: url, targetPixelSize: 1400, failureMode: .transparent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipped()
        }
    }

    /// 顶部可折叠的局信息条:一行摘要,点开看描述/时间/位置/成员。
    @ViewBuilder
    private func roomInfoDisclosure(_ room: KaiXRoomDTO) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { showInfo.toggle() }
            } label: {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: KXRoomStyle.icon(room.typeKey))
                        .kxScaledFont(13, weight: .bold)
                        .foregroundStyle(KXColor.onTint(tint))
                        .frame(width: 30, height: 30)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                    Text(infoSummary(room))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showInfo ? 180 : 0))
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showInfo {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    infoCard(room)
                    membersCard(room)
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.bottom, KXSpacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider().opacity(0.25)
        }
    }

    private func infoSummary(_ room: KaiXRoomDTO) -> String {
        var parts: [String] = []
        if let startsAt = room.starts_at, !startsAt.isEmpty { parts.append(formattedTime(startsAt)) }
        if let hint = room.location_hint, !hint.isEmpty { parts.append(hint) }
        if parts.isEmpty {
            return KXListingCopy.pickText(language, "查看局的详情与成员", "詳細とメンバーを見る", "Tap for details & members")
        }
        return parts.joined(separator: " · ")
    }

    /// 定高、内部滚动的消息区。
    private func chatScroll(_ room: KaiXRoomDTO) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: KXSpacing.md) {
                    if nextBefore != nil {
                        Button {
                            Task { await loadEarlier(proxy: proxy) }
                        } label: {
                            Text(KXListingCopy.pickText(language, "查看更早的消息", "以前のメッセージ", "Earlier messages"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KXColor.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    if visibleMessages.isEmpty {
                        if errorMessage != nil {
                            // room 加载成功、仅 messages 失败:不能伪装成「还没人说话」
                            // 的假空房,给内联重试(轮询也在跑,可自愈)。
                            VStack(spacing: 10) {
                                Image(systemName: "wifi.exclamationmark")
                                    .font(.title2)
                                    .foregroundStyle(.tertiary)
                                Text(KXListingCopy.pickText(language, "消息加载失败", "メッセージを読み込めませんでした", "Couldn't load messages"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button {
                                    Task { await load() }
                                } label: {
                                    Text(KXListingCopy.pickText(language, "重试", "再試行", "Retry"))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(KXColor.accent)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(KXColor.accent.opacity(0.10), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.title2)
                                    .foregroundStyle(.tertiary)
                                Text(joined
                                     ? KXListingCopy.pickText(language, "还没人说话,来开个头", "まだ発言がありません。最初のひとことをどうぞ", "No messages yet — say hi!")
                                     : KXListingCopy.pickText(language, "还没人说话。加入后可以聊天", "まだ発言がありません。参加すると話せます", "No messages yet — join to chat"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        }
                    } else {
                        ForEach(visibleMessages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("chat-bottom")
                        // 底部哨兵可见 ≈ 用户贴底(LazyVStack 预取会把「贴底」判定
                        // 放宽一些,可接受)。iOS 17 目标下没有 onScrollGeometryChange,
                        // 用哨兵 appear/disappear 是零成本的等价探测。
                        .onAppear { isNearBottom = true }
                        .onDisappear { isNearBottom = false }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.vertical, KXSpacing.md)
            }
            .onChange(of: messages.last?.id) { _, _ in
                // 只跟随「尾部新增且用户贴底」:loadEarlier 的头部 prepend 不改变
                // last id 天然不触发;翻历史时轮询到的新消息也不再把人甩回底部(原 bug)。
                guard isNearBottom else { return }
                withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            .onChange(of: forceScrollToBottomTick) { _, _ in
                withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            .onAppear {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func infoCard(_ room: KaiXRoomDTO) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(spacing: KXSpacing.sm) {
                Image(systemName: KXRoomStyle.icon(room.typeKey))
                    .kxScaledFont(16, weight: .bold)
                    .foregroundStyle(KXColor.onTint(tint))
                    .frame(width: 38, height: 38)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(KXRoomStyle.label(room.typeKey, fallback: room.room_type_label, language))
                        .font(.caption.weight(.black))
                        .foregroundStyle(tint)
                    if room.capacityValue > 0 {
                        Text(KXListingCopy.pickText(
                            language,
                            room.memberCountValue >= room.capacityValue ? "已满员" : "还差 \(room.capacityValue - room.memberCountValue) 人",
                            room.memberCountValue >= room.capacityValue ? "満員" : "あと\(room.capacityValue - room.memberCountValue)人",
                            room.memberCountValue >= room.capacityValue ? "Full" : "\(room.capacityValue - room.memberCountValue) spots left"
                        ))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(room.memberCountValue >= room.capacityValue ? KXColor.heat : KXColor.accent)
                    } else {
                        Text(KXListingCopy.pickText(language, "人数不限", "人数制限なし", "No limit"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !room.isOpen {
                    // 房主手动关闭报名(status=closed)语义是「人齐了」,不是「局结束了」。
                    Text(room.status == "closed"
                         ? KXListingCopy.pickText(language, "已成团", "メンバー決定", "Signups closed")
                         : KXListingCopy.pickText(language, "已结束", "終了", "Ended"))
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            if let description = room.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let startsAt = room.starts_at, !startsAt.isEmpty {
                    Label(formattedTime(startsAt), systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let hint = room.location_hint, !hint.isEmpty {
                    Label(hint, systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private func membersCard(_ room: KaiXRoomDTO) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Text(KXListingCopy.pickText(language, "在房间里的人", "参加メンバー", "In this room"))
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KXSpacing.md) {
                    ForEach(room.members ?? [], id: \.id) { member in
                        Button {
                            router.open(.profile(userId: member.id))
                        } label: {
                            VStack(spacing: 5) {
                                KXSocialAvatar(user: member, size: 46)
                                    .overlay(alignment: .bottomTrailing) {
                                        if member.id == room.host_user_id {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 9, weight: .black))
                                                .foregroundStyle(KXColor.onTint(KXColor.rankGold))
                                                .frame(width: 17, height: 17)
                                                .background(KXColor.rankGold.gradient, in: Circle())
                                                .overlay(Circle().stroke(KXColor.cardBackground, lineWidth: 1.4))
                                        }
                                    }
                                Text(member.displayName ?? member.display_name)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 56)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    @ViewBuilder
    private func messageRow(_ message: KaiXRoomMessageDTO) -> some View {
        if message.isSystem {
            Text(message.content)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            let isMine = message.user?.id == currentUser.id
            HStack(alignment: .top, spacing: KXSpacing.sm) {
                if isMine { Spacer(minLength: 40) }
                if !isMine {
                    Button {
                        if let uid = message.user?.id { router.open(.profile(userId: uid)) }
                    } label: {
                        KXSocialAvatar(user: message.user, size: 30)
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                    if !isMine {
                        Text(message.user?.displayName ?? message.user?.display_name ?? "")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    if isMine {
                        bubbleText(message, isMine: true)
                    } else {
                        // Apple 1.2:骚扰发生在气泡上,举报/拉黑就要长按气泡可达,
                        // 不能只藏在对方个人主页里。自己的气泡不挂菜单(空菜单也会
                        // 触发长按抬起动画,徒增困惑)。
                        bubbleText(message, isMine: false)
                            .contextMenu {
                                if let author = message.user {
                                    Button(role: .destructive) {
                                        reportMessage(message)
                                    } label: {
                                        Label(L("reportUser", language), systemImage: "flag")
                                    }
                                    Button(role: .destructive) {
                                        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以拉黑用户。", "ログインするとブロックできます。", "Sign in to block users.")) else { return }
                                        blockTarget = author
                                    } label: {
                                        Label(L("blockUser", language), systemImage: "hand.raised.slash")
                                    }
                                }
                            }
                    }
                    if let created = message.created_at, let date = KXDateParsing.parse(created) {
                        Text(DateFormatterUtils.relativeText(from: date, language: language))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if !isMine { Spacer(minLength: 40) }
            }
        }
    }

    /// 消息气泡本体(自己 / 他人共用;菜单在调用点按归属挂载)。
    private func bubbleText(_ message: KaiXRoomMessageDTO, isMine: Bool) -> some View {
        Text(message.content)
            .font(.subheadline)
            .foregroundStyle(isMine ? KXColor.onAccent : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isMine ? AnyShapeStyle(KXColor.accent.gradient) : AnyShapeStyle(KXColor.softBackground),
                in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
            )
            .frame(maxWidth: 280, alignment: isMine ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func bottomBar(_ room: KaiXRoomDTO) -> some View {
        if joined {
            HStack(spacing: KXSpacing.sm) {
                TextField(
                    KXListingCopy.pickText(language, "说点什么…", "メッセージを入力…", "Say something…"),
                    text: $draft, axis: .vertical
                )
                .font(.subheadline)
                .lineLimit(1...4)
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, 10)
                .kxGlassSurface(radius: KXRadius.hero)
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        KXSpinner(size: 18, lineWidth: 2)
                            .frame(width: 44, height: 44)
                    } else {
                        // 禁用态原是白箭头 + 35% 灰底,浅色模式下对比度不达标;
                        // 改用 secondary 前景 + 低透明度同色底,两种外观下都可辨。
                        let draftEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(draftEmpty ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(KXColor.onAccent))
                            .frame(width: 44, height: 44)
                            .background(draftEmpty ? AnyShapeStyle(Color.secondary.opacity(0.16)) : AnyShapeStyle(KXColor.accent.gradient), in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(KXListingCopy.pickText(language, "发送", "送信", "Send"))
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.vertical, 10)
            .kxGlassBar()
        } else if room.isOpen || room.status == "full" {
            Button {
                Task { await join() }
            } label: {
                HStack(spacing: 8) {
                    if isJoining {
                        KXSpinner(size: 17, lineWidth: 2)
                    } else {
                        Image(systemName: "person.badge.plus")
                            .font(.headline.weight(.bold))
                    }
                    Text(room.status == "full"
                         ? KXListingCopy.pickText(language, "房间已满员", "満員です", "Room is full")
                         : KXListingCopy.pickText(language, "加入这个局", "この局に参加する", "Join this room"))
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(room.status == "full" ? Color.white : KXColor.onTint(tint))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(room.status == "full" ? AnyShapeStyle(Color.secondary.opacity(0.5)) : AnyShapeStyle(tint.gradient), in: Capsule())
            }
            .buttonStyle(KXPressableStyle(scale: 0.97))
            .disabled(isJoining || room.status == "full")
            .padding(.horizontal, KXSpacing.screen)
            .padding(.vertical, 10)
            .kxGlassBar()
        }
    }

    private func formattedTime(_ raw: String) -> String {
        guard let date = KXDateParsing.parse(raw) else { return raw }
        // starts_at 是 UTC 瞬时,约局是日本本地线下聚会,必须固定 JST 渲染——
        // 与活动端 KXEventStyle.timeLine/dateBadge 一致,否则设备时区≠JST 的用户
        // (回国探亲/来日前规划)会把东京 19:00 JST 的局看成 18:00 的错误墙钟。
        // body 求值热路径:用缓存 formatter,别每次做 ICU 模板解析。
        return KXSocialDateFormatters.templated("MMMdEHHmm", language: language, timeZone: KXEventStyle.displayTimeZone(nil)).string(from: date)
    }

    // MARK: - actions

    private func load() async {
        isLoading = room == nil
        errorMessage = nil
        do {
            async let roomTask = KaiXAPIClient.shared.room(roomId)
            async let messagesTask = KaiXAPIClient.shared.roomMessages(roomId)
            room = try await roomTask
            // 进房清零列表未读角标(本地水位推到当前快照)。
            if let count = room?.message_count {
                seenSinceRoomSnapshot = 0
                KXRoomReadMarks.markRead(userId: currentUser.id, roomId: roomId, messageCount: count)
            }
            do {
                let page = try await messagesTask
                messages = page.items
                nextBefore = page.nextBefore
            } catch {
                // room 已成功、仅 messages 失败:原来这里错误被吞(body 的错误态只在
                // room==nil 时展示),用户看到假空房且轮询永不启动。现在记下错误给
                // 聊天区内联重试,并照常启动轮询(轮询 try? 静默重试,可自愈)。
                if Task.isCancelled {
                    isLoading = false
                    return
                }
                if !(error is CancellationError || (error as? URLError)?.code == .cancelled) {
                    errorMessage = error.kaixUserMessage
                }
            }
            isLoading = false
            startPolling()
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                isLoading = false
                return
            }
            errorMessage = error.kaixUserMessage
            isLoading = false
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                await refreshMessagesQuietly()
            }
        }
    }

    private func refreshMessagesQuietly() async {
        guard let page = try? await KaiXAPIClient.shared.roomMessages(roomId) else { return }
        let existing = Set(messages.map(\.id))
        let fresh = page.items.filter { !existing.contains($0.id) }
        if !fresh.isEmpty {
            messages += fresh
            // 人在房里,轮询到的新消息即视为已见(计入快照后增量,离场时并入水位)。
            seenSinceRoomSnapshot += fresh.count
        }
        // 轮询成功 = 消息通道恢复,清掉首载失败留下的内联错误条(room 此时必非 nil,
        // 不会影响整页错误态)。
        if errorMessage != nil { errorMessage = nil }
        let generation = roomMutationGeneration
        if let updated = try? await KaiXAPIClient.shared.room(roomId) {
            // 代际守卫:join/leave 刚落地时,这个 GET 若在 mutation 前后交错,
            // 过期快照会把 viewer_joined 覆写回旧值(输入栏闪回「加入」按钮
            // 最长 8 秒)。列表页有 loadGeneration,此处同理。
            guard generation == roomMutationGeneration else { return }
            room = updated
            // 新快照已包含刚才的增量:重置增量并把已读水位推进到快照值。
            if let count = updated.message_count {
                seenSinceRoomSnapshot = 0
                KXRoomReadMarks.markRead(userId: currentUser.id, roomId: roomId, messageCount: count)
            }
        }
    }

    private func loadEarlier(proxy: ScrollViewProxy) async {
        guard let before = nextBefore else { return }
        guard let page = try? await KaiXAPIClient.shared.roomMessages(roomId, before: before) else { return }
        let existing = Set(messages.map(\.id))
        let fresh = page.items.filter { !existing.contains($0.id) }
        let anchorId = messages.first?.id
        messages = fresh + messages
        nextBefore = page.nextBefore
        // prepend 会把内容顶下去:等这帧布局落地后把原首条钉回顶部,保持阅读位置
        // 不跳(尾部的 chat-bottom 自动滚动只认 last id,不会被 prepend 触发)。
        if !fresh.isEmpty, let anchorId {
            try? await Task.sleep(for: .milliseconds(80))
            proxy.scrollTo(anchorId, anchor: .top)
        }
    }

    private func join() async {
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以加入局。", "ログインすると参加できます。", "Sign in to join.")) else { return }
        isJoining = true
        defer { isJoining = false }
        do {
            let joined = try await KaiXAPIClient.shared.joinRoom(roomId)
            roomMutationGeneration += 1 // 作废在途轮询的过期 room 快照,防 viewer_joined 回滚
            room = joined
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await refreshMessagesQuietly()
        } catch {
            actionTitle = KXListingCopy.pickText(language, "加入失败", "参加できませんでした", "Couldn't join")
            actionMessage = error.kaixUserMessage
        }
    }

    private func leave() async {
        do {
            let result = try await KaiXAPIClient.shared.leaveRoom(roomId)
            roomMutationGeneration += 1 // 同 join:作废在途轮询的过期 room 快照
            if result == nil {
                // 房主退出 → 房间解散。通知列表页剔除(已解散,再点会 404),再回列表。
                NotificationCenter.default.post(name: .kaiXRoomRemoved, object: nil,
                                                userInfo: ["id": roomId, "disbanded": true])
                dismiss()
            } else {
                room = result
                // 成员退出:房间仍在,但「我的局」筛选下应消失。广播让列表按筛选处理。
                NotificationCenter.default.post(name: .kaiXRoomRemoved, object: nil,
                                                userInfo: ["id": roomId, "disbanded": false])
                await refreshMessagesQuietly()
            }
        } catch {
            actionTitle = isHost
                ? KXListingCopy.pickText(language, "解散失败", "解散できませんでした", "Couldn't disband")
                : KXListingCopy.pickText(language, "退出失败", "退出できませんでした", "Couldn't leave")
            actionMessage = error.kaixUserMessage
        }
    }

    private func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let message = try await KaiXAPIClient.shared.sendRoomMessage(roomId, content: content)
            // 8s 轮询可能已先把这条消息拉回来(POST 已落库、响应回传慢):append 前
            // 查重,否则 ForEach 出现重复 id → 双气泡 + SwiftUI 未定义行为警告。
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
            }
            // 自己发的消息立刻计入已见增量:room 快照最长 8s 后才会包含它,发完就退
            // 出不能在列表上给自己挂未读。
            seenSinceRoomSnapshot += 1
            draft = ""
            forceScrollToBottomTick += 1 // 自己发的消息永远滚到底(即使正翻在历史里)
        } catch {
            actionTitle = KXListingCopy.pickText(language, "发送失败", "送信できませんでした", "Couldn't send")
            actionMessage = error.kaixUserMessage
        }
    }

    /// 房主「已成团」:调服务端 PATCH status=closed,新人不能再加入,成员不受影响。
    private func closeRoom() async {
        guard !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        do {
            let updated = try await KaiXAPIClient.shared.closeRoom(roomId)
            roomMutationGeneration += 1 // 作废在途轮询的过期 room 快照,防 status 回滚闪烁
            room = updated
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionTitle = KXListingCopy.pickText(language, "关闭报名失败", "締め切れませんでした", "Couldn't close signups")
            actionMessage = error.kaixUserMessage
        }
    }

    /// 举报房间。服务端没有房间级举报端点(/api/rooms/* 无 report 路由),复用
    /// 用户举报通道、note 里带 room 上下文,后台报表可按 note 定位到房间。
    private func reportRoom(_ room: KaiXRoomDTO) {
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以举报。", "ログインすると通報できます。", "Sign in to report.")) else { return }
        guard let hostId = room.host_user_id, !hostId.isEmpty else { return }
        Task {
            do {
                try await KaiXAPIClient.shared.reportUser(hostId, reason: "other", note: "room:\(room.id) title:\(room.title.prefix(80))")
                actionTitle = KXListingCopy.pickText(language, "举报房间", "ルームを通報", "Report room")
                actionMessage = L("reportRecorded", language)
            } catch {
                actionTitle = KXListingCopy.pickText(language, "举报失败", "通報できませんでした", "Couldn't report")
                actionMessage = error.kaixUserMessage
            }
        }
    }

    /// 举报某条消息的作者。服务端没有消息级举报端点,复用用户举报通道并在 note
    /// 里带 room/message id,足够后台定位这条消息。
    private func reportMessage(_ message: KaiXRoomMessageDTO) {
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以举报。", "ログインすると通報できます。", "Sign in to report.")) else { return }
        guard let authorId = message.user?.id, !authorId.isEmpty else { return }
        Task {
            do {
                try await KaiXAPIClient.shared.reportUser(authorId, reason: "harassment", note: "room:\(roomId) message:\(message.id)")
                actionTitle = L("reportUser", language)
                actionMessage = L("reportRecorded", language)
            } catch {
                actionTitle = KXListingCopy.pickText(language, "举报失败", "通報できませんでした", "Couldn't report")
                actionMessage = error.kaixUserMessage
            }
        }
    }

    /// 拉黑消息作者:服务端落黑名单 + 本地镜像立即过滤其消息(与 ChatView 同款)。
    private func block(_ target: KaiXUserDTO) async {
        do {
            try await KaiXAPIClient.shared.setBlock(target.id, true)
            var ids = blockedUserIds
            ids.insert(target.id)
            blockedUserIdsRaw = ids.sorted().joined(separator: "|")
            actionTitle = L("blockUser", language)
            actionMessage = L("userBlocked", language)
        } catch {
            actionTitle = KXListingCopy.pickText(language, "拉黑失败", "ブロックできませんでした", "Couldn't block")
            actionMessage = error.kaixUserMessage
        }
    }
}
