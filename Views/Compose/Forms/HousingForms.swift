import SwiftUI

struct HousingFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_housing", icon: "house") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedTextField("fld_rent", text: viewModel.doubleBinding(PostAttributeKeys.rent), keyboard: .decimalPad, isRequired: true)
            TypedTextField("fld_currency", text: viewModel.stringBinding(PostAttributeKeys.currency), placeholder: "JPY / CNY / USD")
            TypedTextField("fld_room_type", text: viewModel.stringBinding(PostAttributeKeys.roomType))
            TypedTextField("fld_area", text: viewModel.stringBinding(PostAttributeKeys.area), isRequired: true)
            TypedTextField("fld_nearest_station", text: viewModel.stringBinding(PostAttributeKeys.nearestStation))
            TypedTextField("fld_move_in_date", text: viewModel.stringBinding(PostAttributeKeys.moveInDate))
            TypedTextField("fld_deposit", text: viewModel.stringBinding(PostAttributeKeys.deposit))
            TypedTextField("fld_key_money", text: viewModel.stringBinding(PostAttributeKeys.keyMoney))
            TypedTextField("fld_contact_method", text: viewModel.stringBinding(PostAttributeKeys.contactMethod))
            TypedChoiceRow(
                titleKey: "fld_status",
                selection: viewModel.stringBinding(PostAttributeKeys.status),
                options: [
                    ("available", "status_available"),
                    ("rented", "status_rented"),
                ]
            )
        }
        .onAppear {
            viewModel.seedDefaultAttribute(PostAttributeKeys.currency, "JPY")
            viewModel.seedDefaultAttribute(PostAttributeKeys.status, "available")
        }
    }
}

struct RoommateFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_roommate", icon: "person.2") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedTextField("fld_rent_range", text: viewModel.stringBinding(PostAttributeKeys.rentRange), isRequired: true)
            TypedTextField("fld_area", text: viewModel.stringBinding(PostAttributeKeys.area), isRequired: true)
            TypedTextField("fld_move_in_date", text: viewModel.stringBinding(PostAttributeKeys.moveInDate))
            TypedTextField("fld_lifestyle_tags", text: viewModel.stringBinding(PostAttributeKeys.lifestyleTags), axis: .vertical)
            TypedTextField("fld_requirements", text: viewModel.stringBinding(PostAttributeKeys.requirements), axis: .vertical)
            TypedTextField("fld_contact_method", text: viewModel.stringBinding(PostAttributeKeys.contactMethod))
        }
    }
}
