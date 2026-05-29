import SwiftUI

struct NewsInfoFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel
    let titleKey: String
    let icon: String

    var body: some View {
        TypedFormSection(titleKey: titleKey, icon: icon) {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedTextField("fld_source", text: viewModel.stringBinding(PostAttributeKeys.source))
            TypedTextField("fld_summary", text: viewModel.stringBinding(PostAttributeKeys.summary), axis: .vertical)
            TypedTextField("fld_location", text: viewModel.stringBinding(PostAttributeKeys.location))
            TypedTextField("fld_event_time", text: viewModel.stringBinding(PostAttributeKeys.eventTime))
            TypedTextField("fld_external_url", text: viewModel.stringBinding(PostAttributeKeys.externalURL), placeholder: "https://")
        }
    }
}
