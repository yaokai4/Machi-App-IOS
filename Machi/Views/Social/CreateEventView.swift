import PhotosUI
import SwiftUI

/// 创建活动 —— 人人都能办活动。封面 + 名称 + 时间 + 地点 + 说明,
/// 其余(副标题/人数/价格展示/合作方链接)都是可选,一分钟就能发出来。
struct CreateEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState

    let currentUser: UserEntity

    @State private var title = ""
    @State private var subtitle = ""
    @State private var description = ""
    @State private var category = "party"
    @State private var startsAt = Date().addingTimeInterval(3600 * 24)
    @State private var hasEndTime = false
    @State private var endsAt = Date().addingTimeInterval(3600 * 26)
    @State private var venueName = ""
    @State private var address = ""
    @State private var hasCapacity = false
    @State private var capacity = 20
    @State private var requiresApproval = false
    @State private var priceText = ""
    @State private var externalURL = ""

    @State private var coverItem: PhotosPickerItem?
    @State private var coverImage: UIImage?
    @State private var coverUploadedURL = ""
    @State private var coverUploadedFileID = ""
    @State private var isUploadingCover = false
    /// 封面上传代际:快速连选两张图时,旧的慢上传完成后不得覆写新图的 URL/收尾
    /// 守卫,否则 last-writer-wins 会发布出与预览不符的封面。
    @State private var coverLoadGeneration = 0

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var tint: Color { KXEventStyle.tint(category) }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSubmitting
            && !isUploadingCover
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    coverPicker
                    categoryPicker
                    basicSection
                    timeSection
                    placeSection
                    optionsSection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(KXColor.heat)
                            .padding(.horizontal, KXSpacing.xs)
                    }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, KXSpacing.md)
                .padding(.bottom, 120)
                .kxReadableWidth(700)
            }
            submitBar
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .kxHidesTabBar(reason: .custom("create-event"))
        .onChange(of: coverItem) { _, newValue in
            Task { await loadCover(newValue) }
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
                Text(KXListingCopy.pickText(language, "创建活动", "イベントを作成", "Create event"))
                    .font(.headline.weight(.bold))
                Text(KXListingCopy.pickText(language, "发布后会生成专属活动页与链接", "公開すると専用ページとリンクが作られます", "Publishing creates a shareable event page"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.sm)
        .kxGlassBar(ignoresTopSafeArea: true)
    }

    // MARK: - sections

    private var coverPicker: some View {
        PhotosPicker(selection: $coverItem, matching: .images) {
            ZStack {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 34, weight: .semibold))
                        Text(KXListingCopy.pickText(language, "添加封面(推荐 16:9)", "カバー画像を追加(16:9推奨)", "Add a cover (16:9)"))
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                }
                if isUploadingCover {
                    Color.black.opacity(0.35)
                    KXSpinner(size: 26, lineWidth: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous)
                    .stroke(KXColor.glassStroke.opacity(0.6), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            sectionLabel(KXListingCopy.pickText(language, "活动类型", "カテゴリ", "Category"))
            FlowLayout(spacing: KXSpacing.sm) {
                ForEach(KXEventStyle.orderedKeys + ["other"], id: \.self) { key in
                    let isSelected = category == key
                    let chipTint = KXEventStyle.tint(key)
                    Button {
                        category = key
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: KXEventStyle.icon(key))
                                .font(.caption.weight(.bold))
                            Text(KXEventStyle.label(key, fallback: nil, language))
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(isSelected ? KXColor.onTint(chipTint) : chipTint)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(isSelected ? chipTint : chipTint.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel(KXListingCopy.pickText(language, "活动名称", "イベント名", "Event name"), required: true)
                TextField(KXListingCopy.pickText(language, "例如 涩谷读书会 × Machi", "例:渋谷読書会 × Machi", "e.g. Shibuya Book Club × Machi"), text: $title)
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, KXSpacing.md)
                    .frame(height: 52)
                    .kxGlassSurface(radius: KXRadius.md)
            }
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel(KXListingCopy.pickText(language, "一句话副标题(可选)", "サブタイトル(任意)", "Subtitle (optional)"))
                TextField(KXListingCopy.pickText(language, "例如 本月主题:村上春树", "例:今月のテーマ:村上春樹", "e.g. This month: Haruki Murakami"), text: $subtitle)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, KXSpacing.md)
                    .frame(height: 46)
                    .kxGlassSurface(radius: KXRadius.md)
            }
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel(KXListingCopy.pickText(language, "活动详情", "イベント詳細", "About this event"))
                TextField(
                    KXListingCopy.pickText(language, "流程、费用说明、要带什么、适合谁来…", "流れ、費用、持ち物、対象など…", "Agenda, costs, what to bring, who it's for…"),
                    text: $description, axis: .vertical
                )
                .font(.subheadline)
                .lineLimit(5...12)
                .padding(KXSpacing.md)
                .kxGlassSurface(radius: KXRadius.md)
            }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            sectionLabel(KXListingCopy.pickText(language, "时间", "日時", "When"), required: true)
            DatePicker(
                KXListingCopy.pickText(language, "开始", "開始", "Starts"),
                selection: $startsAt, in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.subheadline.weight(.semibold))
            // 开始时间被推到结束时间之后时,DatePicker 的 `in: startsAt...` 只钳制
            // 显示、不回写已越界的 endsAt binding → 会提交 end<start 的负时长活动。
            // 主动把结束时间随开始时间钳回,保证"看到的值=提交的值"。
            .onChange(of: startsAt) { _, newStart in
                if hasEndTime, endsAt <= newStart {
                    endsAt = newStart.addingTimeInterval(3600)
                }
            }
            Toggle(isOn: $hasEndTime.animation(.snappy(duration: 0.2))) {
                Text(KXListingCopy.pickText(language, "设置结束时间", "終了時刻を設定", "Set an end time"))
                    .font(.subheadline.weight(.semibold))
            }
            .tint(KXColor.accent)
            if hasEndTime {
                DatePicker(
                    KXListingCopy.pickText(language, "结束", "終了", "Ends"),
                    selection: $endsAt, in: startsAt...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private var placeSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            sectionLabel(KXListingCopy.pickText(language, "地点", "場所", "Where"))
            TextField(KXListingCopy.pickText(language, "场地名,例如 SHIBUYA BOOK LOUNGE", "会場名", "Venue name"), text: $venueName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, KXSpacing.md)
                .frame(height: 46)
                .kxGlassSurface(radius: KXRadius.md)
            TextField(KXListingCopy.pickText(language, "详细地址(可选)", "住所(任意)", "Address (optional)"), text: $address)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, KXSpacing.md)
                .frame(height: 46)
                .kxGlassSurface(radius: KXRadius.md)
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            sectionLabel(KXListingCopy.pickText(language, "更多设置(都是可选)", "詳細設定(すべて任意)", "More options (all optional)"))
            Toggle(isOn: $hasCapacity.animation(.snappy(duration: 0.2))) {
                Text(KXListingCopy.pickText(language, "限制名额", "定員を設定", "Limit capacity"))
                    .font(.subheadline.weight(.semibold))
            }
            .tint(KXColor.accent)
            if hasCapacity {
                Stepper(value: $capacity, in: 2...500) {
                    Text(KXListingCopy.pickText(language, "\(capacity) 个名额,满员自动开候补", "定員\(capacity)名(超過は待機リスト)", "\(capacity) spots, waitlist after"))
                        .font(.subheadline.weight(.semibold))
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Toggle(isOn: $requiresApproval.animation(.snappy(duration: 0.2))) {
                    Text(KXListingCopy.pickText(language, "报名需要我审核", "参加に承認が必要", "Require my approval"))
                        .font(.subheadline.weight(.semibold))
                }
                .tint(KXColor.accent)
                Text(KXListingCopy.pickText(language, "开启后报名先待审核,由你逐个通过", "オンにすると承認待ちになり個別に承認します", "Guests wait for your approval before they're in"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel(KXListingCopy.pickText(language, "费用展示", "料金表示", "Price display"))
                TextField(KXListingCopy.pickText(language, "例如 免费 / ¥1,500(现场付)", "例:無料 / ¥1,500(現地払い)", "e.g. Free / ¥1,500 at door"), text: $priceText)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, KXSpacing.md)
                    .frame(height: 46)
                    .kxGlassSurface(radius: KXRadius.md)
                Text(KXListingCopy.pickText(language, "Machi 不代收任何费用;需要售票请填合作方链接。", "Machi は集金しません。チケット販売は外部リンクをご利用ください。", "Machi never collects money — use a partner link for ticketing."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel(KXListingCopy.pickText(language, "合作方售票/详情链接", "チケット / 詳細リンク", "Ticket / partner link"))
                TextField("https://…", text: $externalURL)
                    .font(.subheadline.weight(.semibold))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, KXSpacing.md)
                    .frame(height: 46)
                    .kxGlassSurface(radius: KXRadius.md)
            }
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private var submitBar: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    KXSpinner(size: 17, lineWidth: 2)
                } else {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.bold))
                }
                Text(KXListingCopy.pickText(language, "发布活动", "イベントを公開", "Publish event"))
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(canSubmit ? KXColor.onTint(tint) : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(canSubmit ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.secondary.opacity(0.4)), in: Capsule())
        }
        .buttonStyle(KXPressableStyle(scale: 0.97))
        .disabled(!canSubmit)
        .padding(.horizontal, KXSpacing.screen)
        .padding(.vertical, 10)
        .kxGlassBar()
    }

    private func sectionLabel(_ text: String, required: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            if required {
                Text("*").font(.caption.weight(.black)).foregroundStyle(KXColor.heat)
            }
        }
    }

    // MARK: - actions

    private func loadCover(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        // 新选图立刻作废上一代任务:旧任务的所有状态写入(URL/预览/收尾)都要过
        // 代际比对,否则「选 A(慢)再选 B(快)」时 A 完成后会覆写 coverUploadedURL,
        // 发布出预览是 B、实际封面是 A 的活动。
        coverLoadGeneration += 1
        let generation = coverLoadGeneration
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            if generation == coverLoadGeneration {
                // 上一代可能仍在途且已被作废(不会再写状态/收尾),这里整体重置,
                // 保证预览与 coverUploadedURL 永远成对一致。
                coverImage = nil
                coverUploadedURL = ""
                coverUploadedFileID = ""
                isUploadingCover = false
                errorMessage = KXListingCopy.pickText(language, "封面读取失败,换一张试试", "画像を読み込めませんでした", "Couldn't load that image")
            }
            return
        }
        guard generation == coverLoadGeneration else { return }
        coverImage = image
        coverUploadedURL = "" // 旧图 URL 立刻作废:上传窗口内点发布不能带上旧封面
        coverUploadedFileID = ""
        isUploadingCover = true
        errorMessage = nil
        // 收尾只允许最新代做:旧代清 isUploadingCover 会提前解锁 canSubmit。
        defer { if generation == coverLoadGeneration { isUploadingCover = false } }
        do {
            // 压到 2048 宽以内再传,活动封面不需要原图。
            let resized = image.kxResized(maxDimension: 2048)
            guard let jpeg = resized.jpegData(compressionQuality: 0.82) else {
                if generation == coverLoadGeneration {
                    // 静默 return 会留下「预览有图、实际没传」的假象:清预览并提示。
                    coverImage = nil
                    errorMessage = KXListingCopy.pickText(language, "封面处理失败,换一张试试", "画像を処理できませんでした", "Couldn't process that image")
                }
                return
            }
            let uploaded = try await KaiXAPIClient.shared.uploadFile(
                data: jpeg,
                mime: "image/jpeg",
                fileName: "event-cover.jpg",
                purpose: "event_cover",
                entityType: "event",
                width: Int(resized.size.width),
                height: Int(resized.size.height)
            )
            guard generation == coverLoadGeneration else { return }
            coverUploadedURL = uploaded.media.publicUrl ?? uploaded.media.url ?? ""
            coverUploadedFileID = uploaded.file.id
        } catch {
            guard generation == coverLoadGeneration else { return }
            coverImage = nil
            coverUploadedURL = ""
            coverUploadedFileID = ""
            errorMessage = error.kaixUserMessage
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let region = RegionStore.shared.current
            var payload = KaiXAPIClient.CreateEventPayload(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                starts_at: KXDateParsing.iso.string(from: startsAt)
            )
            payload.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            payload.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
            payload.category = category
            payload.cover_url = coverUploadedURL
            payload.cover_file_id = coverUploadedFileID
            // 兜底:即便 UI 钳制被绕过,也绝不提交早于开始时间的结束时间
            // (否则服务端按 COALESCE(ends,starts) 归类会把未来活动判成"往期"而消失)。
            payload.ends_at = hasEndTime ? KXDateParsing.iso.string(from: max(endsAt, startsAt.addingTimeInterval(3600))) : ""
            payload.venue_name = venueName.trimmingCharacters(in: .whitespacesAndNewlines)
            payload.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
            payload.country_code = region?.countryCode ?? "jp"
            payload.city_slug = region?.cityCode ?? ""
            payload.region_code = region?.regionCode ?? ""
            payload.capacity = hasCapacity ? capacity : 0
            payload.requires_approval = requiresApproval
            payload.price_text = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
            payload.external_url = externalURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let event = try await KaiXAPIClient.shared.createEvent(payload)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSubmitting = false
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                router.open(.eventDetail(idOrSlug: event.slug ?? event.id))
            }
        } catch {
            isSubmitting = false
            errorMessage = error.kaixUserMessage
        }
    }
}

private extension UIImage {
    func kxResized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
