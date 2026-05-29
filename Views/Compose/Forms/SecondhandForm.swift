import SwiftUI

struct SecondhandFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_secondhand", icon: "tag") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedTextField("fld_price", text: viewModel.doubleBinding(PostAttributeKeys.price), keyboard: .decimalPad, isRequired: true)
            TypedTextField("fld_currency", text: viewModel.stringBinding(PostAttributeKeys.currency), placeholder: "JPY / CNY / USD")
            TypedTextField("fld_condition", text: viewModel.stringBinding(PostAttributeKeys.condition))
            TypedTextField("fld_trade_method", text: viewModel.stringBinding(PostAttributeKeys.tradeMethod))
            TypedTextField("fld_area", text: viewModel.stringBinding(PostAttributeKeys.area), isRequired: true)
            TypedChoiceRow(
                titleKey: "fld_status",
                selection: viewModel.stringBinding(PostAttributeKeys.status),
                options: [
                    ("available", "status_available"),
                    ("reserved", "status_reserved"),
                    ("sold", "status_sold"),
                ]
            )
        }
        .onAppear {
            viewModel.seedDefaultAttribute(PostAttributeKeys.currency, "JPY")
            viewModel.seedDefaultAttribute(PostAttributeKeys.status, "available")
        }
    }
}
