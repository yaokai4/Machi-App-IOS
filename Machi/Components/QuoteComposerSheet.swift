import SwiftUI

/// Full quote-repost composer sheet: multi-line editor + quoted-post
/// preview card + character budget, replacing the old single-line
/// `.alert` TextField. Publishing reuses the existing quote pipeline —
/// the sheet only collects text and hands it to `onSubmit` (the same
/// `onQuoteRepost` closure the card already wires to
/// `PostRepository.quoteRepost`).
struct QuoteComposerSheet: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool
    @State private var text = ""

    let post: PostEntity
    let author: UserEntity?
    var mediaItems: [MediaEntity] = []
    let onSubmit: (String) -> Void

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canPublish: Bool {
        !trimmed.isEmpty && text.count <= KaiXConfig.maxPostCharacters
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    editor
                    quotedPreview
                }
                .padding(KXSpacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)
            .kxPageBackground()
            .navigationTitle(L("quotePost", language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("cancel", language)) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("publish", language)) {
                        // Fire-and-forget on purpose: every call site wraps
                        // onQuoteRepost in its own Task with optimistic
                        // update + rollback toast, mirroring the old alert
                        // flow. The sheet closes immediately.
                        onSubmit(trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canPublish)
                    .accessibilityIdentifier("quote_composer_publish")
                }
            }
        }
        .onAppear { isEditorFocused = true }
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(L("quotePlaceholder", language))
                        .font(KXTypography.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(KXTypography.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 132, maxHeight: 240)
                    .focused($isEditorFocused)
                    .accessibilityLabel(L("quotePlaceholder", language))
                    .accessibilityIdentifier("quote_composer_editor")
            }
            .padding(KXSpacing.sm)
            .kxGlassSurface(radius: KXRadius.lg)

            characterCounter
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Same budget behavior as the main composer: invisible while well
    /// within the limit, thin progress ring from 75 %, remaining count
    /// (red when negative) from 90 %.
    @ViewBuilder
    private var characterCounter: some View {
        let limit = KaiXConfig.maxPostCharacters
        let count = text.count
        let progress = min(1.0, Double(count) / Double(limit))
        let over = count > limit
        let remaining = limit - count

        if progress >= 0.75 || over {
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

    // MARK: - Quoted post preview

    /// Static preview of the post being quoted — deliberately
    /// non-interactive (no media viewer, no profile jump) so the sheet
    /// stays a single-purpose composer.
    private var quotedPreview: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack(spacing: KXSpacing.xs) {
                KXAvatar(user: author, size: KXAvatarSize.xs)
                Text(author?.displayName ?? L("unknownUser", language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                KXUserBadge(user: author)
                Text("@\(author?.username ?? L("unknownUser", language))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if !post.previewText.isEmpty {
                Text(post.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !mediaItems.isEmpty {
                MediaGridView(mediaItems: mediaItems)
            }
        }
        .padding(KXSpacing.md)
        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .stroke(KXColor.separator, lineWidth: 0.6)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
