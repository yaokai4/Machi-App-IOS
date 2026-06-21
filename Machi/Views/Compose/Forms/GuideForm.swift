import SwiftUI

struct GuideFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_guide", icon: "book") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedTextField("fld_cover_image", text: viewModel.stringBinding(PostAttributeKeys.coverImage), placeholder: "https://")
            TypedTextField("fld_summary", text: viewModel.stringBinding(PostAttributeKeys.summary), axis: .vertical)
            TypedTextField("fld_last_updated", text: viewModel.stringBinding(PostAttributeKeys.lastUpdatedAt))
        }
    }
}
