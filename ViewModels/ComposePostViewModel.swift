import Foundation
import Combine
import SwiftData
import SwiftUI

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
    @Published private(set) var publishedPost: PostEntity?
    /// Region the post will be tagged with. Defaults to whatever the
    /// user is currently browsing (RegionStore), but can be overridden
    /// per-post — e.g. someone in Shanghai posting a Tokyo travel tip.
    @Published var selectedRegion: KaiXRegionDirectory.Region? = RegionStore.shared.current
    /// Content type. Picked up front (see ContentTypePickerView) and
    /// may be changed mid-composition through the header chip; the
    /// generic body (text / media / tags) survives the swap.
    @Published var contentType: ContentType = .dynamic
    /// Typed attribute values for the current contentType. Mutated
    /// directly by the per-type form sub-views via binding.
    @Published var attributes: [String: KaiXAttributeValue] = [:]
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
            get: { self.attributes[key]?.doubleValue.map { "\(Int($0))" } ?? "" },
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

    var hasDraft: Bool {
        canPublish
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
        case .image_post, .long_post, .rant, .anonymous:
            return [PostAttributeKeys.title]
        case .news, .local_info:
            return [PostAttributeKeys.title]
        case .guide:
            return [PostAttributeKeys.title]
        case .question:
            return [PostAttributeKeys.question]
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
            return [PostAttributeKeys.title, PostAttributeKeys.meetupTime]
        case .dining:
            return [PostAttributeKeys.restaurantOrArea, PostAttributeKeys.meetupTime]
        case .event:
            return [PostAttributeKeys.title, PostAttributeKeys.eventTime]
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
        if let s = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return true
        }
        if let d = value.doubleValue, d != 0 || (value.stringValue?.isEmpty == false) {
            return true
        }
        if value.boolValue != nil {
            return true
        }
        return false
    }

    private var hasRequiredTypedAttributes: Bool {
        missingRequiredAttributeKeys.isEmpty
    }

    func loadSuggestedTopics(context: ModelContext) async {
        do {
            let topics = try await TopicRepository(context: context).fetchTrending(limit: 24)
            suggestedTopics = randomizedSuggestedTopics(from: topics.map(\.name))
        } catch {
            suggestedTopics = randomizedSuggestedTopics(from: [])
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

    func addMedia(data: Data, isVideo: Bool, language: AppLanguage) async {
        state = .loading
        errorMessage = nil

        guard mediaDrafts.count < KaiXConfig.maxMediaItemsPerPost else {
            state = .loaded
            return
        }

        do {
            let draft = isVideo
                ? try await UploadService.shared.prepareVideo(data: data)
                : try await UploadService.shared.prepareImage(data: data)
            mediaDrafts.append(draft)
            state = .loaded
        } catch {
            errorMessage = L("mediaFailed", language)
            state = .error(errorMessage ?? L("mediaFailed", language))
        }
    }

    func removeMedia(_ draft: MediaDraft) {
        mediaDrafts.removeAll { $0.id == draft.id }
    }

    func reportMediaFailure(language: AppLanguage) {
        errorMessage = L("permissionDenied", language)
        state = .error(errorMessage ?? L("mediaFailed", language))
    }

    func publish(context: ModelContext, currentUser: UserEntity, language: AppLanguage) async -> Bool {
        commitTopicDraft()
        guard canPublish else { return false }
        isPublishing = true
        state = .loading
        errorMessage = nil
        publishedPost = nil
        defer { isPublishing = false }

        do {
            let post = try await PostRepository(context: context).createPost(
                authorId: currentUser.id,
                content: content,
                mediaDrafts: mediaDrafts,
                hashtags: selectedTopics,
                region: selectedRegion,
                contentType: contentType,
                attributes: attributes,
                language: selectedLanguage.serverTag
            )
            publishedPost = post
            content = ""
            mediaDrafts = []
            topicDraft = ""
            selectedTopics = []
            attributes = [:]
            contentType = .dynamic
            state = .loaded
            return true
        } catch {
            errorMessage = L("failedToPost", language)
            state = .error(errorMessage ?? error.kaixUserMessage)
            return false
        }
    }

    func saveDraft(context: ModelContext, currentUser: UserEntity, language: AppLanguage) async -> Bool {
        commitTopicDraft()
        guard canPublish else { return false }
        state = .loading
        errorMessage = nil

        do {
            _ = try await PostRepository(context: context).saveDraft(
                authorId: currentUser.id,
                content: content,
                mediaDrafts: mediaDrafts,
                hashtags: selectedTopics,
                region: selectedRegion,
                contentType: contentType,
                attributes: attributes,
                language: selectedLanguage.serverTag
            )
            content = ""
            mediaDrafts = []
            topicDraft = ""
            selectedTopics = []
            attributes = [:]
            contentType = .dynamic
            state = .loaded
            return true
        } catch {
            errorMessage = L("databaseSaveFailed", language)
            state = .error(errorMessage ?? error.kaixUserMessage)
            return false
        }
    }

    private func randomizedSuggestedTopics(from topics: [String]) -> [String] {
        let normalized = topics.normalizedDisplayHashtags
        return Array(normalized.shuffled().prefix(8))
    }
}
