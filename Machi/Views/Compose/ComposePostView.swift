import PhotosUI
import SwiftData
import SwiftUI

struct ComposePostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var composeStore: ComposeStore
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var toastManager: ToastManager
    @StateObject private var viewModel = ComposePostViewModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showDiscardDialog = false
    @State private var isShowingRegionPicker = false
    @State private var isShowingTypePicker = false
    @State private var showMembership = false

    let currentUser: UserEntity

    /// High-trust content type chosen but the user isn't a verified
    /// member yet. The server enforces this too (403 MEMBERSHIP_REQUIRED);
    /// this gates the UX and routes to the membership page.
    private var needsMembership: Bool {
        viewModel.contentType.requiresVerifiedMembership && !currentUser.isVerifiedMember
    }
    /// Optional pre-selection — passed in when the composer is
    /// opened from the type-picker entry flow so the user doesn't
    /// have to re-pick. Falls back to .dynamic.
    var initialContentType: ContentType? = nil
    var onPublished: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        typeRow
                        if needsMembership { membershipGate }
                        composer
                        typedForm
                        missingFieldsHint
                        regionLanguageRow
                        topicComposer
                        suggestedTopicChips
                        mediaPreview
                        uploadState
                    }
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }

                bottomToolbar
            }
            .kxPageBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog(L("discardDraftTitle", language), isPresented: $showDiscardDialog, titleVisibility: .visible) {
            Button(L("saveDraft", language)) {
                Task {
                    if await viewModel.saveDraft(context: modelContext, currentUser: currentUser, language: language) {
                        composeStore.clear()
                        onPublished()
                        dismiss()
                    }
                }
            }
            Button(L("discard", language), role: .destructive) { dismiss() }
            Button(L("keepEditing", language), role: .cancel) {}
        }
        .onChange(of: pickerItems) { _, newValue in
            Task {
                for item in newValue {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        viewModel.reportMediaFailure(language: language)
                        continue
                    }
                    let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                    await viewModel.addMedia(data: data, isVideo: isVideo, language: language)
                }
                pickerItems = []
            }
        }
        .task {
            if let initial = initialContentType, viewModel.contentType == .dynamic {
                viewModel.setContentType(initial)
            }
            await viewModel.loadSuggestedTopics(context: modelContext)
        }
        .onChange(of: viewModel.content) { _, _ in
            syncComposeStore()
        }
        .onChange(of: viewModel.mediaDrafts) { _, _ in
            syncComposeStore()
        }
        .onChange(of: viewModel.selectedTopics) { _, _ in
            syncComposeStore()
        }
        .sheet(isPresented: $showMembership) {
            NavigationStack { MembershipView(currentUser: currentUser) }
        }
    }

    /// Inline notice shown when a member-only content type is selected by
    /// a non-member. Tapping the button opens the membership page.
    private var membershipGate: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
                Text(L("composeMembershipRequired", language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                showMembership = true
            } label: {
                Text(L("composeMembershipCTA", language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(KXColor.accent))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(KXColor.softBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(KXColor.accent.opacity(0.3), lineWidth: 0.8))
    }

    private func syncComposeStore() {
        composeStore.setDraft(
            content: viewModel.content,
            media: viewModel.mediaDrafts,
            tags: viewModel.selectedTopics
        )
    }

    private var header: some View {
        HStack {
            Button(L("cancel", language)) {
                if viewModel.hasDraft {
                    showDiscardDialog = true
                } else {
                    dismiss()
                }
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(.primary)

            Spacer()

            Text(L("compose", language))
                .font(.headline.weight(.semibold))

            Spacer()

            Button {
                if needsMembership {
                    showMembership = true
                    return
                }
                Task {
                    let ok = await viewModel.publish(context: modelContext, currentUser: currentUser, language: language)
                    if ok {
                        if let post = viewModel.publishedPost {
                            postStore.insertPublishedPost(post, currentUserId: currentUser.id)
                        }
                        composeStore.clear()
                        onPublished()
                        dismiss()
                    } else {
                        toastManager.show(.requestFailed(message: L("composePublishFailed", language), technicalDetails: viewModel.errorMessage))
                    }
                }
            } label: {
                if viewModel.isPublishing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(L("postingEllipsis", language))
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text(L("publish", language))
                        .font(.headline.weight(.semibold))
                }
            }
            .foregroundStyle(viewModel.canPublish ? .white : .secondary)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(viewModel.canPublish ? KXColor.accent : KXColor.softBackground)
            )
            .overlay(
                Capsule()
                    .stroke(viewModel.canPublish ? KXColor.accent.opacity(0.4) : KXColor.separator, lineWidth: 0.7)
            )
            .opacity(viewModel.canPublish ? 1.0 : 0.65)
            .disabled(!viewModel.canPublish || viewModel.isPublishing)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    /// Type chip + picker entry. Composer always starts from a content
    /// type — either passed in via `initialContentType` from the type
    /// picker sheet, or the default `.dynamic`. Switching here clears
    /// the typed-form attributes but preserves the body / media so a
    /// half-typed dynamic post can be promoted to e.g. secondhand
    /// without losing the photos.
    private var typeRow: some View {
        let spec = viewModel.contentType.spec
        return Button {
            isShowingTypePicker = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(spec.tint.opacity(0.16))
                    Image(systemName: spec.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(spec.tint)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L(spec.titleKey, language))
                        .font(.subheadline.weight(.semibold))
                    Text(L(spec.subtitleKey, language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .kxGlassSurface(radius: KXRadius.md)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowingTypePicker) {
            ContentTypePickerView(current: viewModel.contentType) { type in
                viewModel.setContentType(type)
            }
        }
    }

    /// Typed-form switchboard now lives in `ComposeFormFactory` so the
    /// dispatch stays out of the view's body when more types arrive.
    private var typedForm: some View {
        ComposeFormFactory(viewModel: viewModel)
    }

    /// Author can override the per-post region + language without
    /// leaving the composer. Region defaults to RegionStore.shared.current,
    /// language defaults to the user's resolved primary content
    /// language. Both are sent to the server in `publish()`.
    private var regionLanguageRow: some View {
        HStack(spacing: 10) {
            Button {
                isShowingRegionPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KXColor.accent)
                    if let region = viewModel.selectedRegion {
                        Text("\(region.countryEmoji) \(region.cityName)")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    } else {
                        Text(L("pickRegion", language))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .kxGlassCapsule()
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Menu {
                ForEach([ContentLanguage.zh, .en, .ja, .ko, .fr, .es], id: \.self) { lang in
                    Button {
                        viewModel.selectedLanguage = lang
                    } label: {
                        if viewModel.selectedLanguage == lang {
                            Label(lang.title(language), systemImage: "checkmark")
                        } else {
                            Text(lang.title(language))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KXColor.accent)
                    Text(viewModel.selectedLanguage.title(language))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .kxGlassCapsule()
                .foregroundStyle(.primary)
            }
        }
        .sheet(isPresented: $isShowingRegionPicker) {
            RegionPickerView(
                initialCountry: currentUser.country.isEmpty ? (viewModel.selectedRegion?.countryCode ?? "jp") : currentUser.country,
                allowsAnyCountry: false
            ) { region in
                viewModel.selectedRegion = region
            }
        }
    }

    /// Inline hint surfacing the field names the user still needs to
    /// fill before the publish button enables. Hidden when valid.
    @ViewBuilder
    private var missingFieldsHint: some View {
        let missing = viewModel.missingRequiredAttributeKeys
        if !missing.isEmpty && viewModel.contentType.hasTypedForm {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.heat)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("composeMissingHeader", language))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(missing.map { L($0, language) }.joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, KXSpacing.md)
            .padding(.vertical, 10)
            .background(KXColor.heat.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(KXColor.heat.opacity(0.25), lineWidth: 0.7)
            )
        }
    }

    private var composer: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(user: currentUser, size: 48)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.content)
                    .font(.title3)
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(.top, -8)

                if viewModel.content.isEmpty {
                    Text(L("placeholderPost", language))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(16)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private var topicComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(L("addTopicPlaceholder", language), text: $viewModel.topicDraft)
                    .font(.subheadline.weight(.semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        viewModel.commitTopicDraft()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .kxGlassCapsule()

                Button {
                    viewModel.commitTopicDraft()
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .kxGlassCapsule()
                }
                .buttonStyle(.plain)
                .disabled(viewModel.topicDraft.normalizedTopicName.isEmpty)
                .foregroundStyle(viewModel.topicDraft.normalizedTopicName.isEmpty ? .secondary : KXColor.accent)
            }

            if !viewModel.selectedTopics.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.selectedTopics, id: \.self) { topic in
                        Button {
                            viewModel.removeTopic(topic)
                        } label: {
                            HStack(spacing: 5) {
                                Text("#\(topic)")
                                Image(systemName: "xmark.circle.fill")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .kxGlassCapsule()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var suggestedTopicChips: some View {
        let topics = viewModel.suggestedTopics.filter { topic in
            !viewModel.selectedTopics.map(\.normalizedTopicName).contains(topic.normalizedTopicName)
        }

        return VStack(alignment: .leading, spacing: 8) {
            if !topics.isEmpty {
                Text(L("recommendedTopics", language))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(topics, id: \.self) { topic in
                        Button {
                            viewModel.addTopic(topic)
                        } label: {
                            Text("#\(topic)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .kxGlassCapsule()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if !viewModel.mediaDrafts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("mediaPreview", language))
                    .font(.headline.weight(.semibold))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.mediaDrafts) { draft in
                            ZStack(alignment: .topTrailing) {
                                CachedMediaImageView(url: draft.thumbnailURL)
                                    .frame(width: 148, height: 148)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .overlay(alignment: .bottomLeading) {
                                        if draft.type == .video {
                                            Label(durationText(draft.duration), systemImage: "play.fill")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 5)
                                                .background(.black.opacity(0.72))
                                                .clipShape(Capsule())
                                                .padding(8)
                                        }
                                    }

                                Button {
                                    viewModel.removeMedia(draft)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, .black.opacity(0.7))
                                }
                                .padding(8)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var uploadState: some View {
        if let errorMessage = viewModel.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                Text(errorMessage)
                Spacer()
                Button(L("retry", language)) {
                    viewModel.errorMessage = nil
                }
                .font(.caption.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.red)
            .padding(12)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }

        if viewModel.isPublishing || viewModel.state == .loading {
            HStack(spacing: 10) {
                ProgressView()
                Text(viewModel.isPublishing ? L("postingEllipsis", language) : L("processingMedia", language))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .kxGlassSurface(radius: KXRadius.md)
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 18) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: KaiXConfig.maxMediaItemsPerPost, matching: .images) {
                Image(systemName: "photo")
                    .font(.title3.weight(.semibold))
            }
            .disabled(viewModel.mediaDrafts.count >= KaiXConfig.maxMediaItemsPerPost)

            PhotosPicker(selection: $pickerItems, maxSelectionCount: KaiXConfig.maxMediaItemsPerPost, matching: .videos) {
                Image(systemName: "video")
                    .font(.title3.weight(.semibold))
            }
            .disabled(viewModel.mediaDrafts.count >= KaiXConfig.maxMediaItemsPerPost)

            Spacer()

            characterCounter
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .kxGlassBar()
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }

    /// Counter design: stays invisible while the user is well within
    /// the budget, fades in as a thin progress ring once you cross
    /// 75 %, and flips to a remaining-character readout (negative,
    /// red) once you go over. Lower-key than the old fixed `n/280`
    /// label that nagged users from word one.
    @ViewBuilder
    private var characterCounter: some View {
        let limit = KaiXConfig.maxPostCharacters
        let count = viewModel.content.count
        let progress = min(1.0, Double(count) / Double(limit))
        let warningThreshold = 0.75
        let over = count > limit
        let remaining = limit - count

        if progress >= warningThreshold || over {
            HStack(spacing: 6) {
                if over {
                    Text("\(remaining)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else if progress >= 0.9 {
                    Text("\(remaining)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            over ? Color.red : (progress >= 0.9 ? Color.orange : Color.secondary),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.12), value: progress)
                }
                .frame(width: 16, height: 16)
            }
            .transition(.opacity)
        }
    }

    private func durationText(_ duration: Double) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
