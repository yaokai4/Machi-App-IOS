import SwiftUI

/// Shared "title + optional summary" form used by image_post,
/// long_post, rant, anonymous-ish posts where the body is the
/// dominant payload but a title still helps the card view.
struct BasicTitleFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel
    let titleKey: String
    let icon: String
    var includesSummary = false
    var includesCategory = false

    var body: some View {
        TypedFormSection(titleKey: titleKey, icon: icon) {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            if includesSummary {
                TypedTextField("fld_summary", text: viewModel.stringBinding(PostAttributeKeys.summary), axis: .vertical)
            }
            if includesCategory {
                TypedTextField("fld_category", text: viewModel.stringBinding(PostAttributeKeys.category))
            }
        }
    }
}

struct QuestionFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_question", icon: "questionmark.bubble") {
            TypedTextField("fld_question", text: viewModel.stringBinding(PostAttributeKeys.question), axis: .vertical, isRequired: true)
            TypedTextField("fld_category", text: viewModel.stringBinding(PostAttributeKeys.category))
        }
    }
}

struct AnonymousFormView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_anonymous", icon: "eye.slash") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title))
            TypedTextField("fld_description", text: viewModel.stringBinding(PostAttributeKeys.description), axis: .vertical, isRequired: true)
            Toggle(isOn: viewModel.boolBinding(PostAttributeKeys.anonymous)) {
                Text(L("fld_anonymous", language))
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)
        }
        .onAppear {
            if viewModel.attributes[PostAttributeKeys.anonymous] == nil {
                viewModel.attributes[PostAttributeKeys.anonymous] = KaiXAttributeValue(bool: true)
            }
        }
    }
}

struct PollFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_poll", icon: "chart.bar") {
            TypedTextField("fld_question", text: viewModel.stringBinding(PostAttributeKeys.question), axis: .vertical, isRequired: true)
            TypedTextField("fld_poll_options", text: viewModel.stringBinding(PostAttributeKeys.options), placeholder: "选项 A / 选项 B / 选项 C", axis: .vertical, isRequired: true)
            TypedTextField("fld_expires_at", text: viewModel.stringBinding(PostAttributeKeys.expiresAt))
        }
    }
}
