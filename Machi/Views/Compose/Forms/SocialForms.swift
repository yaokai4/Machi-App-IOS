import SwiftUI

struct MeetupFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_meetup", icon: "hand.wave") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedTextField("fld_meetup_type", text: viewModel.stringBinding(PostAttributeKeys.meetupType))
            TypedTextField("fld_meetup_time", text: viewModel.stringBinding(PostAttributeKeys.meetupTime))
            TypedTextField("fld_location", text: viewModel.stringBinding(PostAttributeKeys.location))
            TypedTextField("fld_people_limit", text: viewModel.intBinding(PostAttributeKeys.peopleLimit), keyboard: .numberPad)
            TypedTextField("fld_budget", text: viewModel.stringBinding(PostAttributeKeys.budget))
            TypedTextField("fld_description", text: viewModel.stringBinding(PostAttributeKeys.description), axis: .vertical)
            TypedTextField("safetyNotice", text: viewModel.stringBinding(PostAttributeKeys.safetyNotice), axis: .vertical)
        }
    }
}

struct DiningFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_dining", icon: "fork.knife") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title))
            TypedTextField("fld_restaurant_or_area", text: viewModel.stringBinding(PostAttributeKeys.restaurantOrArea), isRequired: true)
            TypedTextField("fld_meetup_time", text: viewModel.stringBinding(PostAttributeKeys.meetupTime))
            TypedTextField("fld_people_limit", text: viewModel.intBinding(PostAttributeKeys.peopleLimit), keyboard: .numberPad)
            TypedTextField("fld_budget", text: viewModel.stringBinding(PostAttributeKeys.budget))
            TypedTextField("fld_description", text: viewModel.stringBinding(PostAttributeKeys.description), axis: .vertical)
        }
    }
}

struct EventFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_event", icon: "calendar") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedTextField("fld_event_time", text: viewModel.stringBinding(PostAttributeKeys.eventTime))
            TypedTextField("fld_location", text: viewModel.stringBinding(PostAttributeKeys.location))
            TypedTextField("fld_fee", text: viewModel.stringBinding(PostAttributeKeys.fee))
            TypedTextField("fld_capacity", text: viewModel.intBinding(PostAttributeKeys.capacity), keyboard: .numberPad)
            TypedTextField("fld_registration", text: viewModel.stringBinding(PostAttributeKeys.registrationMethod))
            TypedTextField("fld_description", text: viewModel.stringBinding(PostAttributeKeys.description), axis: .vertical)
        }
    }
}
