import Foundation
import Combine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ComposePostViewModel: ObservableObject {
    @Published var content = ""
    @Published var mediaDrafts: [MediaDraft] = []
    @Published var topicDraft = ""
    @Published var selectedTopics: [String] = []
    @Published var suggestedTopics: [String] = []
    @Published var state: ScreenState = .idle
    @Published var isPublishing = false
    @Published var errorMessage: String?
    @Published private(set) var mediaUploadStates: [String: UploadState] = [:]
    @Published private(set) var mediaUploadProgress: [String: Double] = [:]
    @Published private(set) var publishedPost: PostEntity?
    private var uploadedMediaByDraftID: [String: KaiXMediaDTO] = [:]
    private var mediaUploadTasks: [String: Task<Void, Never>] = [:]
    /// Region the post will be tagged with. Defaults to whatever the
    /// user is currently browsing (RegionStore), but can be overridden
    /// per-post — e.g. someone in Shanghai posting a Tokyo travel tip.
    @Published var selectedRegion: KaiXRegionDirectory.Region? = RegionStore.shared.current

    /// 实际随发布/存草稿下发的地区(客户端双保险的第一层)。
    /// init 默认值在 VM 创建那一刻取 RegionStore.current——若当时 store 还没
    /// 水合(冷启动直进发帖/登录回放未完成),selectedRegion 会一直是 nil;
    /// 这里在发出前再兜底读一次当前地区,与服务端的地区兜底互为双保险,
    /// 不动 selectedRegion 本身(用户显式清除/选择的语义保持不变)。
    private var outgoingRegion: KaiXRegionDirectory.Region? {
        selectedRegion ?? RegionStore.shared.current
    }
    /// Content type. Picked up front (see ContentTypePickerView) and
    /// may be changed mid-composition through the header chip; the
    /// generic body (text / media / tags) survives the swap.
    @Published var contentType: ContentType = .dynamic
    /// Typed attribute values for the current contentType. Mutated
    /// directly by the per-type form sub-views via binding.
    @Published var attributes: [String: KaiXAttributeValue] = [:]
    /// Keys the typed forms auto-seed with a default value on first
    /// appearance (currency=JPY, status=available, job_type=part_time,
    /// review_status=under_review, anonymous=true, …), together with the
    /// value we seeded. Kept so `hasDraft` can tell "user merely opened a
    /// typed form" (only untouched defaults present) apart from "user
    /// actually started a draft". Without this, picking a content type
    /// would immediately pop the discard-confirmation dialog on Cancel and
    /// let a blank draft (only defaults, no title/price/body) be saved.
    private var seededDefaultAttributes: [String: KaiXAttributeValue] = [:]
    /// Explicit content-language tag for the post. Default is the
    /// user's resolved preferred content language (so a JP-living user
    /// posting in Japanese gets `ja` automatically). Author can
    /// override per-post via the LanguagePicker chip in the composer.
    @Published var selectedLanguage: ContentLanguage = LanguageManager.shared
        .resolvedPrimary(for: AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? "")) ?? .zh

    var canPublish: Bool {
        if content.count > KaiXConfig.maxPostCharacters { return false }
        let hasGenericPayload = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !mediaDrafts.isEmpty
            || !selectedTopics.isEmpty
            || hasPendingTopic
        guard !hasPendingMediaUploads, !hasFailedMediaUploads else { return false }
        // Two ways to be "publishable":
        //   1) the typed form has its small set of required fields
        //      filled (e.g. secondhand: title + price), OR
        //   2) the user wrote enough generic content (body / media /
        //      tag) — useful when they pick a type but want to just
        //      type a free-form post.
        // Earlier versions required *all* the type's fields, which
        // blocked publishing for anyone exploring the form. The
        // detail view tolerates missing optional fields anyway.
        if contentType.hasTypedForm {
            // Body-first 类型(图文/长文/吐槽/匿名)的 required 集合为空,
            // 「空集合恒满足」不能等同于「可发布」——否则正文/媒体/话题全空
            // 也能点发布,产出空白帖或只剩服务端一句笼统失败。此时回退为
            // 与 .dynamic 相同的 hasGenericPayload 要求。
            if requiredAttributeKeys.isEmpty { return hasGenericPayload }
            return hasRequiredTypedAttributes || hasGenericPayload
        }
        return hasGenericPayload
    }

    /// Switch content type and clear typed attributes so a stale field
    /// from the previous form can't leak into the new payload.
    /// Generic body (text/media/tags) intentionally survives so the
    /// user doesn't lose what they've already typed.
    func setContentType(_ type: ContentType) {
        guard type != contentType else { return }
        contentType = type
        attributes = [:]
        seededDefaultAttributes = [:]
    }

    /// Typed binding helpers — string / double / int / bool — bound to
    /// the typed-form sub-views so each field can write back into
    /// `attributes` with the right value flavour.
    func stringBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { self.attributes[key]?.stringValue ?? "" },
            set: { newValue in
                if newValue.isEmpty { self.attributes.removeValue(forKey: key) }
                else { self.attributes[key] = KaiXAttributeValue(string: newValue) }
            }
        )
    }
    func doubleBinding(_ key: String) -> Binding<String> {
        Binding(
            get: {
                guard let n = self.attributes[key]?.doubleValue else { return "" }
                // Render whole numbers without ".0" so the field stays
                // tidy for "4200" style price input.
                return n.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(n))" : "\(n)"
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    self.attributes.removeValue(forKey: key)
                } else if let n = Double(trimmed) {
                    self.attributes[key] = KaiXAttributeValue(double: n)
                }
            }
        )
    }
    func intBinding(_ key: String) -> Binding<String> {
        Binding(
            get: {
                guard let number = self.attributes[key]?.doubleValue else { return "" }
                return "\(Int(number))"
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    self.attributes.removeValue(forKey: key)
                } else if let n = Int(trimmed) {
                    self.attributes[key] = KaiXAttributeValue(double: Double(n))
                }
            }
        )
    }
    func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { self.attributes[key]?.boolValue ?? false },
            set: { newValue in
                self.attributes[key] = KaiXAttributeValue(bool: newValue)
            }
        )
    }

    func setStringAttribute(_ key: String, _ value: String) {
        if value.isEmpty {
            attributes.removeValue(forKey: key)
        } else {
            attributes[key] = KaiXAttributeValue(string: value)
        }
    }

    /// Seed a default *string* value for `key` when the field is still
    /// empty, remembering it as a seeded default so it doesn't, by itself,
    /// make the composer look like it has an unsaved draft. Called by the
    /// typed forms on appear (currency=JPY, status=available, …).
    func seedFormDefault(_ key: String, _ value: String) {
        guard attributes[key] == nil else { return }
        let seeded = KaiXAttributeValue(string: value)
        attributes[key] = seeded
        seededDefaultAttributes[key] = seeded
    }

    /// Seed a default *bool* value for `key` (e.g. anonymous=true) when the
    /// field is still empty, remembering it as a seeded default.
    func seedFormDefault(_ key: String, _ value: Bool) {
        guard attributes[key] == nil else { return }
        let seeded = KaiXAttributeValue(bool: value)
        attributes[key] = seeded
        seededDefaultAttributes[key] = seeded
    }

    var hasDraft: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !mediaDrafts.isEmpty
            || !selectedTopics.isEmpty
            || hasPendingTopic
            || hasUserEnteredAttributes
    }

    /// True when `attributes` holds at least one value the user actually
    /// entered — anything that isn't a still-untouched seeded default. A
    /// seeded field starts equal to the value we seeded; once the user
    /// changes it (edits the currency, flips the anonymous toggle, taps a
    /// different status chip) its value no longer matches and it counts.
    private var hasUserEnteredAttributes: Bool {
        attributes.contains { key, value in
            seededDefaultAttributes[key] != value
        }
    }

    var hasPendingMediaUploads: Bool {
        mediaUploadStates.contains { id, uploadState in
            guard uploadState == .compressing || uploadState == .uploading || uploadState == .waiting else {
                return false
            }
            if mediaDrafts.contains(where: { $0.id == id }) {
                return KaiXBackend.token != nil && uploadedMediaByDraftID[id] == nil
            }
            return uploadState == .compressing
        }
    }

    var hasFailedMediaUploads: Bool {
        mediaDrafts.contains { draft in
            mediaUploadStates[draft.id] == .failed && uploadedMediaByDraftID[draft.id] == nil
        }
    }

    /// 选大视频后 prepareVideo(内部可能有数十秒的 1080p 转码)期间 draft
    /// 尚未 append 进 mediaDrafts,.compressing 状态只挂在临时 preparingId
    /// 上。必须单独暴露这个阶段,否则转码全程界面毫无反馈、像卡死。
    var isPreparingMedia: Bool {
        mediaUploadStates.contains { id, uploadState in
            uploadState == .compressing && !mediaDrafts.contains(where: { $0.id == id })
        }
    }

    var shouldShowUploadProgress: Bool {
        // 准备/转码阶段 mediaDrafts 还是空的,也要显示"处理中"横幅
        // (视图侧 uploadProgressText 为空时回退到 processingMedia 文案)。
        if isPreparingMedia { return true }
        return !mediaDrafts.isEmpty && (hasPendingMediaUploads || hasFailedMediaUploads || isPublishing)
    }

    var uploadProgressText: String {
        uploadProgressText(language: .zh)
    }

    func uploadProgressText(language: AppLanguage) -> String {
        guard !mediaDrafts.isEmpty else { return "" }
        let uploaded = mediaDrafts.filter { mediaUploadStates[$0.id] == .uploaded }.count
        let percent = Int((overallUploadProgress * 100).rounded())
        if hasFailedMediaUploads {
            return L("mediaUploadFailedRetry", language)
        }
        if isPublishing {
            return String(format: L("mediaUploadPublishedCount", language), uploaded, mediaDrafts.count)
        }
        return uploaded == mediaDrafts.count
            ? L("mediaUploadComplete", language)
            : String(format: L("mediaUploadProgress", language), uploaded, mediaDrafts.count, percent)
    }

    var overallUploadProgress: Double {
        guard !mediaDrafts.isEmpty else { return isPublishing ? 0.98 : 0 }
        let total = mediaDrafts.reduce(0.0) { partial, draft in
            partial + (mediaUploadProgress[draft.id] ?? (mediaUploadStates[draft.id] == .uploaded ? 1 : 0))
        }
        return min(max(total / Double(mediaDrafts.count), 0), 1)
    }

    private var hasPendingTopic: Bool {
        !topicDraft.normalizedTopicName.isEmpty
    }

    /// Per-type required field keys. Trimmed to the **smallest set**
    /// that still produces a useful card — over-requiring fields was
    /// blocking publish for anyone who hadn't filled every optional
    /// row. The detail view re-rendering tolerates missing values, so
    /// extra signals stay opt-in.
    ///
    /// Convention: title (or the type's primary identifier) plus one
    /// hard-to-rebuild signal (price, rent, time, contact). Everything
    /// else is captured by the typed form but not required.
    var requiredAttributeKeys: [String] {
        switch contentType {
        case .image_post, .long_post, .rant, .anonymous, .question:
            // Body-first posts: the composer body / media is the content,
            // so nothing in the typed form is required. 提问的正文就是问题,
            // 发布时自动镜像进 attributes.question(见 publish)。
            return []
        case .news, .local_info:
            return [PostAttributeKeys.title]
        case .guide:
            return [PostAttributeKeys.title]
        case .secondhand:
            return [PostAttributeKeys.title, PostAttributeKeys.price]
        case .housing:
            return [PostAttributeKeys.title, PostAttributeKeys.rent]
        case .roommate:
            return [PostAttributeKeys.title]
        case .job_seek:
            return [PostAttributeKeys.desiredJob]
        case .job_post:
            return [PostAttributeKeys.jobTitle, PostAttributeKeys.companyName]
        case .referral:
            return [PostAttributeKeys.jobTitle]
        case .meetup:
            return [PostAttributeKeys.title]
        case .dining:
            return [PostAttributeKeys.restaurantOrArea]
        case .event:
            return [PostAttributeKeys.title]
        case .service:
            return [PostAttributeKeys.serviceType]
        case .merchant:
            return [PostAttributeKeys.merchantName]
        case .coupon:
            return [PostAttributeKeys.title, PostAttributeKeys.discountInfo]
        case .warning:
            return [PostAttributeKeys.title]
        case .poll:
            return [PostAttributeKeys.question, PostAttributeKeys.options]
        default:
            return []
        }
    }

    /// Subset of `requiredAttributeKeys` that the user hasn't filled
    /// yet. Empty list means the form is valid.
    var missingRequiredAttributeKeys: [String] {
        requiredAttributeKeys.filter { key in
            !isAttributeFilled(key)
        }
    }

    private func isAttributeFilled(_ key: String) -> Bool {
        guard let value = attributes[key] else { return false }
        if let s = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return !s.isEmpty
        }
        // A numeric value counts as filled even when it is 0 (e.g. a free /
        // ¥0 price), and any explicit boolean counts as filled too.
        if value.doubleValue != nil { return true }
        if value.boolValue != nil { return true }
        return false
    }

    private var hasRequiredTypedAttributes: Bool {
        missingRequiredAttributeKeys.isEmpty
    }

    func loadSuggestedTopics(context: ModelContext) async {
        do {
            let topics = try await TopicRepository(context: context).fetchTrending(limit: 24)
            suggestedTopics = deterministicSuggestedTopics(from: topics.map(\.name))
        } catch {
            suggestedTopics = []
        }
    }

    func addTopic(_ topic: String) {
        let normalized = topic.normalizedTopicName
        guard !normalized.isEmpty else { return }
        guard !selectedTopics.map(\.normalizedTopicName).contains(normalized) else {
            topicDraft = ""
            return
        }
        selectedTopics.append(normalized)
        topicDraft = ""
    }

    func commitTopicDraft() {
        addTopic(topicDraft)
    }

    func removeTopic(_ topic: String) {
        let normalized = topic.normalizedTopicName
        selectedTopics.removeAll { $0.normalizedTopicName == normalized }
    }

    func addMedia(data: Data, isVideo: Bool, contentType: UTType? = nil, language: AppLanguage) async {
        state = .loading
        errorMessage = nil

        let hasVideo = mediaDrafts.contains { $0.type == .video }
        let imageCount = mediaDrafts.filter { $0.type == .image }.count
        if isVideo {
            guard mediaDrafts.isEmpty else {
                errorMessage = L(hasVideo ? "mediaVideoLimit" : "mediaVideoOnlyOne", language)
                state = .error(errorMessage ?? L("mediaFailed", language))
                return
            }
            guard data.count <= KaiXConfig.maxPostVideoSourceBytes else {
                errorMessage = L("mediaTooLarge", language)
                state = .error(errorMessage ?? L("mediaFailed", language))
                return
            }
        } else {
            guard !hasVideo else {
                errorMessage = L("mediaVideoOnlyOne", language)
                state = .error(errorMessage ?? L("mediaFailed", language))
                return
            }
            guard imageCount < KaiXConfig.maxImageItemsPerPost else {
                errorMessage = L("mediaImageLimit", language)
                state = .error(errorMessage ?? L("mediaFailed", language))
                return
            }
            guard data.count <= KaiXConfig.maxPostImageSourceBytes else {
                errorMessage = L("mediaTooLarge", language)
                state = .error(errorMessage ?? L("mediaFailed", language))
                return
            }
        }

        do {
            let preparingId = UUID().uuidString
            mediaUploadStates[preparingId] = .compressing
            defer { mediaUploadStates.removeValue(forKey: preparingId) }
            let draft = isVideo
                ? try await UploadService.shared.prepareVideo(data: data, contentType: contentType)
                : try await UploadService.shared.prepareImage(data: data)
            mediaDrafts.append(draft)
            mediaUploadStates[draft.id] = KaiXBackend.token == nil ? .local : .waiting
            mediaUploadProgress[draft.id] = 0
            state = .loaded
            startUpload(for: draft, language: language)
        } catch UploadService.UploadError.mediaTooLarge {
            errorMessage = L("mediaTooLarge", language)
            state = .error(errorMessage ?? L("mediaFailed", language))
        } catch UploadService.UploadError.emptyMedia {
            errorMessage = L("mediaVideoIncomplete", language)
            state = .error(errorMessage ?? L("mediaFailed", language))
        } catch {
            errorMessage = L("mediaFailed", language)
            state = .error(errorMessage ?? L("mediaFailed", language))
        }
    }

    func addVideo(fileURL: URL, contentType: UTType? = nil, language: AppLanguage) async {
        state = .loading
        errorMessage = nil

        let hasVideo = mediaDrafts.contains { $0.type == .video }
        guard mediaDrafts.isEmpty else {
            errorMessage = L(hasVideo ? "mediaVideoLimit" : "mediaVideoOnlyOne", language)
            state = .error(errorMessage ?? L("mediaFailed", language))
            return
        }
        guard fileByteCount(at: fileURL) <= KaiXConfig.maxPostVideoSourceBytes else {
            errorMessage = L("mediaTooLarge", language)
            state = .error(errorMessage ?? L("mediaFailed", language))
            return
        }

        do {
            let preparingId = UUID().uuidString
            mediaUploadStates[preparingId] = .compressing
            defer { mediaUploadStates.removeValue(forKey: preparingId) }
            let draft = try await UploadService.shared.prepareVideo(fileURL: fileURL, contentType: contentType)
            mediaDrafts.append(draft)
            mediaUploadStates[draft.id] = KaiXBackend.token == nil ? .local : .waiting
            mediaUploadProgress[draft.id] = 0
            state = .loaded
            startUpload(for: draft, language: language)
        } catch UploadService.UploadError.mediaTooLarge {
            errorMessage = L("mediaTooLarge", language)
            state = .error(errorMessage ?? L("mediaFailed", language))
        } catch UploadService.UploadError.emptyMedia {
            errorMessage = L("mediaVideoIncomplete", language)
            state = .error(errorMessage ?? L("mediaFailed", language))
        } catch {
            errorMessage = L("mediaFailed", language)
            state = .error(errorMessage ?? L("mediaFailed", language))
        }
    }

    func removeMedia(_ draft: MediaDraft) {
        mediaUploadTasks[draft.id]?.cancel()
        mediaUploadTasks.removeValue(forKey: draft.id)
        let uploaded = uploadedMediaByDraftID.removeValue(forKey: draft.id)
        mediaDrafts.removeAll { $0.id == draft.id }
        mediaUploadStates.removeValue(forKey: draft.id)
        mediaUploadProgress.removeValue(forKey: draft.id)
        // 同步清掉 KaiXMedia 里的暂存副本(视频最大 200MB),不再只靠启动时
        // 48h 老化回收。上传任务已先 cancel,其失败回调会因 draft 已移除而
        // 提前 return,不会闪出错误条。
        Task { await UploadService.shared.cleanupDraftFiles(draft) }
        if let uploaded {
            Task { try? await KaiXAPIClient.shared.deleteUploadedFile(uploaded.id) }
        }
    }

    func reportMediaFailure(language: AppLanguage) {
        // loadTransferable 返回 nil 多半是 iCloud 原件没下完/格式不支持/
        // 传输中断,与相册权限无关——权限不足时 PhotosPicker 根本不会交出
        // item。之前误用 permissionDenied 会把用户引去改系统设置,无济于事。
        errorMessage = KXListingCopy.pickText(
            language,
            "无法读取所选文件，请稍后重试。",
            "選択したファイルを読み込めませんでした。しばらくしてからもう一度お試しください。",
            "Couldn't load the selected file. Please try again."
        )
        state = .error(errorMessage ?? L("mediaFailed", language))
    }

    private func fileByteCount(at url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? Int.max
    }

    func publish(context: ModelContext, currentUser: UserEntity, language: AppLanguage) async -> Bool {
        commitTopicDraft()
        guard canPublish else { return false }
        guard !isPublishing else { return false }
        guard !hasPendingMediaUploads else {
            errorMessage = L("mediaUploadStillRunning", language)
            state = .error(errorMessage ?? L("failedToPost", language))
            return false
        }
        guard !hasFailedMediaUploads else {
            errorMessage = L("mediaUploadFailedRetry", language)
            state = .error(errorMessage ?? L("failedToPost", language))
            return false
        }
        isPublishing = true
        state = .loading
        errorMessage = nil
        publishedPost = nil
        for draft in mediaDrafts where uploadedMediaByDraftID[draft.id] != nil {
            mediaUploadStates[draft.id] = .uploaded
            mediaUploadProgress[draft.id] = 1
        }
        defer { isPublishing = false }

        do {
            let post = try await PostRepository(context: context).createPost(
                authorId: currentUser.id,
                content: content,
                mediaDrafts: mediaDrafts,
                hashtags: publishHashtags,
                region: outgoingRegion,
                contentType: contentType,
                attributes: outgoingAttributes,
                language: selectedLanguage.serverTag,
                uploadedMediaByDraftID: uploadedMediaByDraftID,
                onMediaUploadState: { [weak self] draftId, uploadState, progress in
                    Task { @MainActor in
                        guard let self else { return }
                        self.mediaUploadStates[draftId] = uploadState
                        self.mediaUploadProgress[draftId] = uploadState == .uploaded ? 1 : progress
                    }
                },
                onMediaUploaded: { [weak self] draftId, media in
                    Task { @MainActor in
                        self?.uploadedMediaByDraftID[draftId] = media
                    }
                }
            )
            publishedPost = post
            resetDraft(keepError: false)
            state = .loaded
            return true
        } catch let apiError as KaiXAPIError {
            markPendingUploadsFailed()
            errorMessage = apiError.error.message
            state = .error(errorMessage ?? L("failedToPost", language))
            return false
        } catch UploadService.UploadError.mediaTooLarge {
            markPendingUploadsFailed()
            errorMessage = L("mediaTooLarge", language)
            state = .error(errorMessage ?? L("failedToPost", language))
            return false
        } catch {
            markPendingUploadsFailed()
            errorMessage = "\(L("failedToPost", language))：\(error.kaixUserMessage)"
            state = .error(errorMessage ?? L("failedToPost", language))
            return false
        }
    }

    func saveDraft(context: ModelContext, currentUser: UserEntity, language: AppLanguage) async -> Bool {
        commitTopicDraft()
        // 草稿本就未定稿——不要求 canPublish(typed form 必填项可以缺,
        // 仓库层有自己的"至少有点内容"校验)。但媒体上传进行中/失败时仍要
        // 拦下:仓库存草稿会同步重传未完成媒体,与在飞的上传任务撞车会重复
        // 上传。之前 guard canPublish 静默 return false,用户点「保存草稿」
        // 却毫无反馈;现在每个拦截都写明原因(视图侧对 false 弹 toast)。
        guard hasDraft else { return false }
        if content.count > KaiXConfig.maxPostCharacters {
            errorMessage = KXListingCopy.pickText(
                language,
                "正文超出字数上限，请精简后再保存。",
                "本文が文字数の上限を超えています。短くしてから保存してください。",
                "Post exceeds the character limit. Please shorten it before saving."
            )
            state = .error(errorMessage ?? L("databaseSaveFailed", language))
            return false
        }
        guard !hasPendingMediaUploads else {
            errorMessage = KXListingCopy.pickText(
                language,
                "媒体还在处理，请等它完成后再保存草稿。",
                "メディアを処理中です。完了してから下書きを保存してください。",
                "Media is still processing. Please wait for it to finish before saving the draft."
            )
            state = .error(errorMessage ?? L("databaseSaveFailed", language))
            return false
        }
        guard !hasFailedMediaUploads else {
            errorMessage = L("mediaUploadFailedRetry", language)
            state = .error(errorMessage ?? L("databaseSaveFailed", language))
            return false
        }
        state = .loading
        errorMessage = nil

        do {
            _ = try await PostRepository(context: context).saveDraft(
                authorId: currentUser.id,
                content: content,
                mediaDrafts: mediaDrafts,
                hashtags: publishHashtags,
                region: outgoingRegion,
                contentType: contentType,
                attributes: outgoingAttributes,
                language: selectedLanguage.serverTag,
                uploadedMediaByDraftID: uploadedMediaByDraftID
            )
            resetDraft(keepError: false)
            state = .loaded
            return true
        } catch {
            errorMessage = L("databaseSaveFailed", language)
            state = .error(errorMessage ?? error.kaixUserMessage)
            return false
        }
    }

    private func deterministicSuggestedTopics(from topics: [String]) -> [String] {
        let normalized = topics.normalizedDisplayHashtags
        return Array(normalized.prefix(8))
    }

    private var publishHashtags: [String] {
        (selectedTopics + content.extractedHashtags).normalizedDisplayHashtags
    }

    /// Attributes as they go to the server. 提问的正文就是问题本身(独立
    /// 「问题」表单已删),这里把正文首段镜像进 attributes.question,Web /
    /// 老版本客户端按 question 属性渲染的地方照常工作。
    private var outgoingAttributes: [String: KaiXAttributeValue] {
        guard contentType == .question else { return attributes }
        var merged = attributes
        let question = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !question.isEmpty {
            merged[PostAttributeKeys.question] = KaiXAttributeValue(string: String(question.prefix(300)))
        }
        return merged
    }

    func resetDraft(keepError: Bool = false) {
        cancelUploadTasks()
        // 发布成功/存草稿/丢弃后主动清理 KaiXMedia 暂存副本,不再只靠启动
        // 48h/500MB 老化。本地兜底构建(DEBUG 测试)例外:local 帖/草稿的
        // MediaEntity 直接引用这些文件路径,删了媒体会变黑图。
        if !KaiXRuntimeFlags.allowLocalStoreFallback, !mediaDrafts.isEmpty {
            let staged = mediaDrafts
            Task {
                for draft in staged {
                    await UploadService.shared.cleanupDraftFiles(draft)
                }
            }
        }
        content = ""
        mediaDrafts = []
        topicDraft = ""
        selectedTopics = []
        attributes = [:]
        seededDefaultAttributes = [:]
        contentType = .dynamic
        mediaUploadStates = [:]
        mediaUploadProgress = [:]
        uploadedMediaByDraftID = [:]
        if !keepError {
            errorMessage = nil
        }
    }

    func discardDraftAndDeleteUploads(keepError: Bool = false) async {
        let uploaded = uploadedMediaByDraftID
        resetDraft(keepError: keepError)
        await deleteUploadedMedia(uploaded)
    }

    func clearPublishErrorForRetry() {
        errorMessage = nil
        state = mediaDrafts.isEmpty ? .idle : .loaded
        for draft in mediaDrafts where uploadedMediaByDraftID[draft.id] != nil {
            mediaUploadStates[draft.id] = .uploaded
            mediaUploadProgress[draft.id] = 1
        }
    }

    func retryFailedMediaUploads(language: AppLanguage) {
        errorMessage = nil
        state = .loaded
        for draft in mediaDrafts where mediaUploadStates[draft.id] == .failed && uploadedMediaByDraftID[draft.id] == nil {
            startUpload(for: draft, language: language)
        }
    }

    private func startUpload(for draft: MediaDraft, language: AppLanguage) {
        guard KaiXBackend.token != nil else {
            mediaUploadStates[draft.id] = .local
            mediaUploadProgress[draft.id] = 1
            return
        }
        mediaUploadTasks[draft.id]?.cancel()
        mediaUploadStates[draft.id] = .uploading
        mediaUploadProgress[draft.id] = max(mediaUploadProgress[draft.id] ?? 0, 0.01)
        mediaUploadTasks[draft.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let uploaded = try await UploadService.shared.upload(
                    draft: draft,
                    purpose: draft.type == .video ? "post_video" : "post_image",
                    entityType: "post"
                ) { progress in
                    Task { @MainActor in
                        guard self.mediaDrafts.contains(where: { $0.id == draft.id }) else { return }
                        self.mediaUploadStates[draft.id] = .uploading
                        self.mediaUploadProgress[draft.id] = min(max(progress, 0.01), 0.99)
                    }
                }
                guard !Task.isCancelled else { return }
                guard self.mediaDrafts.contains(where: { $0.id == draft.id }) else {
                    try? await KaiXAPIClient.shared.deleteUploadedFile(uploaded.id)
                    return
                }
                self.uploadedMediaByDraftID[draft.id] = uploaded
                self.mediaUploadStates[draft.id] = .uploaded
                self.mediaUploadProgress[draft.id] = 1
                self.mediaUploadTasks.removeValue(forKey: draft.id)
                self.state = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                guard self.mediaDrafts.contains(where: { $0.id == draft.id }) else { return }
                self.mediaUploadStates[draft.id] = .failed
                self.mediaUploadProgress[draft.id] = 0
                self.mediaUploadTasks.removeValue(forKey: draft.id)
                self.errorMessage = "\(L("mediaUploadFailed", language))：\(error.kaixUserMessage)"
                self.state = .error(self.errorMessage ?? L("mediaFailed", language))
            }
        }
    }

    private func cancelUploadTasks() {
        for task in mediaUploadTasks.values {
            task.cancel()
        }
        mediaUploadTasks.removeAll()
    }

    private func deleteUploadedMedia(_ uploadedMedia: [String: KaiXMediaDTO]) async {
        let ids = Array(Set(uploadedMedia.values.map(\.id)))
        for id in ids {
            try? await KaiXAPIClient.shared.deleteUploadedFile(id)
        }
    }

    private func markPendingUploadsFailed() {
        for draft in mediaDrafts where mediaUploadStates[draft.id] != .uploaded && uploadedMediaByDraftID[draft.id] == nil {
            mediaUploadStates[draft.id] = .failed
        }
    }
}
