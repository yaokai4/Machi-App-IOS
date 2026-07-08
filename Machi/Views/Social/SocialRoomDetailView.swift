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
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var showLeaveConfirm = false
    /// 局信息默认收起——聊天优先。点顶部信息条展开(描述/时间/位置/成员)。
    @State private var showInfo = false
    /// 轻量轮询:房间聊天没有专用推送通道,前台每 8s 刷一次新消息。
    @State private var pollTask: Task<Void, Never>?

    private var tint: Color { KXRoomStyle.tint(room?.typeKey ?? "chat") }
    private var joined: Bool { room?.joined ?? false }
    private var isHost: Bool { room?.isHostViewer ?? false }

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
        .onDisappear { pollTask?.cancel() }
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
        .alert(KXListingCopy.pickText(language, "提示", "お知らせ", "Notice"), isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
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
            if joined {
                Menu {
                    if isHost {
                        Button(role: .destructive) {
                            showLeaveConfirm = true
                        } label: {
                            Label(KXListingCopy.pickText(language, "解散房间", "ルームを解散", "Disband room"), systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive) {
                            showLeaveConfirm = true
                        } label: {
                            Label(KXListingCopy.pickText(language, "退出这个局", "ルームを退出", "Leave room"), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .kxGlassCircle()
                }
            }
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.sm)
        .kxGlassBar(ignoresTopSafeArea: true)
    }

    /// 聊天 App 式布局:可折叠的局信息条 + 定高内部滚动的消息区 + 底部固定操作。
    /// 关键是消息区用 `.frame(maxHeight: .infinity)` 吃掉剩余空间自己滚,不会把
    /// 整页越撑越长(之前的 bug)。
    private func content(_ room: KaiXRoomDTO) -> some View {
        VStack(spacing: 0) {
            roomInfoDisclosure(room)
            chatScroll(room)
            bottomBar(room)
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
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showInfo {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    infoCard(room)
                    membersCard(room)
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
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
                            Task { await loadEarlier() }
                        } label: {
                            Text(KXListingCopy.pickText(language, "查看更早的消息", "以前のメッセージ", "Earlier messages"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KXColor.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    if messages.isEmpty {
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
                    } else {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("chat-bottom")
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.vertical, KXSpacing.md)
            }
            .onChange(of: messages.count) { _, _ in
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
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    Text(KXListingCopy.pickText(language, "已结束", "終了", "Closed"))
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
                                                .foregroundStyle(.white)
                                                .frame(width: 17, height: 17)
                                                .background(Color.orange.gradient, in: Circle())
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
                    Text(message.content)
                        .font(.subheadline)
                        .foregroundStyle(isMine ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isMine ? AnyShapeStyle(KXColor.accent.gradient) : AnyShapeStyle(KXColor.softBackground),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .frame(maxWidth: 280, alignment: isMine ? .trailing : .leading)
                        .fixedSize(horizontal: false, vertical: true)
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
                .kxGlassSurface(radius: 22)
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        KXSpinner(size: 18, lineWidth: 2)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AnyShapeStyle(Color.secondary.opacity(0.35)) : AnyShapeStyle(KXColor.accent.gradient), in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(KXListingCopy.pickText(language, "发送", "送信", "Send"))
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
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
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(room.status == "full" ? AnyShapeStyle(Color.secondary.opacity(0.5)) : AnyShapeStyle(tint.gradient), in: Capsule())
            }
            .buttonStyle(KXPressableStyle(scale: 0.97))
            .disabled(isJoining || room.status == "full")
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.vertical, 10)
            .kxGlassBar()
        }
    }

    private func formattedTime(_ raw: String) -> String {
        guard let date = KXDateParsing.parse(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .ja ? "ja_JP" : (language == .en ? "en_US" : "zh_CN"))
        formatter.setLocalizedDateFormatFromTemplate("MMMdEHHmm")
        return formatter.string(from: date)
    }

    // MARK: - actions

    private func load() async {
        isLoading = room == nil
        errorMessage = nil
        do {
            async let roomTask = KaiXAPIClient.shared.room(roomId)
            async let messagesTask = KaiXAPIClient.shared.roomMessages(roomId)
            room = try await roomTask
            let page = try await messagesTask
            messages = page.items
            nextBefore = page.nextBefore
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
        }
        if let updated = try? await KaiXAPIClient.shared.room(roomId) {
            room = updated
        }
    }

    private func loadEarlier() async {
        guard let before = nextBefore else { return }
        guard let page = try? await KaiXAPIClient.shared.roomMessages(roomId, before: before) else { return }
        let existing = Set(messages.map(\.id))
        messages = page.items.filter { !existing.contains($0.id) } + messages
        nextBefore = page.nextBefore
    }

    private func join() async {
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以加入局。", "ログインすると参加できます。", "Sign in to join.")) else { return }
        isJoining = true
        defer { isJoining = false }
        do {
            room = try await KaiXAPIClient.shared.joinRoom(roomId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await refreshMessagesQuietly()
        } catch {
            actionMessage = error.kaixUserMessage
        }
    }

    private func leave() async {
        do {
            let result = try await KaiXAPIClient.shared.leaveRoom(roomId)
            if result == nil {
                // 房主退出 → 房间解散,直接回列表。
                dismiss()
            } else {
                room = result
                await refreshMessagesQuietly()
            }
        } catch {
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
            messages.append(message)
            draft = ""
        } catch {
            actionMessage = error.kaixUserMessage
        }
    }
}
