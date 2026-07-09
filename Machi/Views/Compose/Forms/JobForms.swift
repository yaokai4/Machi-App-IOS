import SwiftUI

struct JobSeekFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_jobseek", icon: "briefcase") {
            TypedTextField("fld_desired_job", text: viewModel.stringBinding(PostAttributeKeys.desiredJob), isRequired: true)
            TypedTextField("fld_skills", text: viewModel.stringBinding(PostAttributeKeys.skills), axis: .vertical)
            TypedTextField("fld_languages", text: viewModel.stringBinding(PostAttributeKeys.languages))
            TypedTextField("fld_visa_status", text: viewModel.stringBinding(PostAttributeKeys.visaStatus))
            TypedTextField("fld_availability", text: viewModel.stringBinding(PostAttributeKeys.availability))
            TypedTextField("fld_expected_salary", text: viewModel.stringBinding(PostAttributeKeys.expectedSalary))
            TypedTextField("fld_resume_url", text: viewModel.stringBinding(PostAttributeKeys.resumeURL), placeholder: "https://")
            TypedTextField("fld_contact_method", text: viewModel.stringBinding(PostAttributeKeys.contactMethod))
        }
    }
}

struct JobPostFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel
    @Environment(\.appLanguage) private var language

    var body: some View {
        TypedFormSection(titleKey: "ct_jobpost", icon: "building.2") {
            TypedTextField("fld_job_title", text: viewModel.stringBinding(PostAttributeKeys.jobTitle), isRequired: true)
            TypedTextField("fld_company_name", text: viewModel.stringBinding(PostAttributeKeys.companyName), isRequired: true)
            TypedTextField("fld_salary", text: viewModel.stringBinding(PostAttributeKeys.salary))
            TypedChoiceRow(
                titleKey: "fld_job_type",
                selection: viewModel.stringBinding(PostAttributeKeys.jobType),
                options: [
                    ("full_time", "jt_full_time"),
                    ("part_time", "jt_part_time"),
                    ("internship", "jt_internship"),
                    ("remote", "jt_remote"),
                ]
            )
            TypedTextField("fld_language_req", text: viewModel.stringBinding(PostAttributeKeys.languageRequirement))
            TypedTextField("fld_visa_req", text: viewModel.stringBinding(PostAttributeKeys.visaRequirement))
            TypedTextField("fld_work_location", text: viewModel.stringBinding(PostAttributeKeys.workLocation))
            TypedTextField("fld_contact_method", text: viewModel.stringBinding(PostAttributeKeys.contactMethod))
            Toggle(isOn: viewModel.boolBinding(PostAttributeKeys.companyVerified)) {
                Text(L("companyVerified", language))
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)
        }
        .onAppear {
            viewModel.seedFormDefault(PostAttributeKeys.jobType, "part_time")
        }
    }
}

struct ReferralFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_referral", icon: "person.crop.circle.badge.checkmark") {
            TypedTextField("fld_job_title", text: viewModel.stringBinding(PostAttributeKeys.jobTitle), isRequired: true)
            TypedTextField("fld_company_name", text: viewModel.stringBinding(PostAttributeKeys.companyName))
            TypedTextField("fld_work_location", text: viewModel.stringBinding(PostAttributeKeys.workLocation))
            TypedTextField("fld_contact_method", text: viewModel.stringBinding(PostAttributeKeys.contactMethod))
            TypedTextField("fld_description", text: viewModel.stringBinding(PostAttributeKeys.description), axis: .vertical)
        }
    }
}
