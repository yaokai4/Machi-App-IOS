import SwiftUI

/// Single dispatch point that picks the right typed form for a given
/// ContentType. `ComposePostView` no longer has to switch through
/// 22 cases inline — it just embeds this view and lets the factory
/// route. Returns `EmptyView` for the generic-payload types so the
/// composer falls through to the simple "text + media" form.
struct ComposeFormFactory: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        switch viewModel.contentType {
        case .dynamic:
            EmptyView()

        case .image_post:
            // 摘要对图文帖冗余(图片/正文已是主体),去掉只留标题。
            BasicTitleFormView(viewModel: viewModel, titleKey: "ct_image", icon: "photo.on.rectangle")

        case .long_post:
            BasicTitleFormView(viewModel: viewModel, titleKey: "ct_long", icon: "doc.text", includesSummary: true)

        case .rant:
            BasicTitleFormView(viewModel: viewModel, titleKey: "ct_rant", icon: "speaker.wave.2")

        case .question:
            QuestionFormView(viewModel: viewModel)

        case .news:
            NewsInfoFormView(viewModel: viewModel, titleKey: "ct_news", icon: "newspaper")

        case .local_info:
            NewsInfoFormView(viewModel: viewModel, titleKey: "ct_localinfo", icon: "megaphone")

        case .guide:
            GuideFormView(viewModel: viewModel)

        case .secondhand:
            SecondhandFormView(viewModel: viewModel)

        case .housing:
            HousingFormView(viewModel: viewModel)

        case .roommate:
            RoommateFormView(viewModel: viewModel)

        case .job_seek:
            JobSeekFormView(viewModel: viewModel)

        case .job_post:
            JobPostFormView(viewModel: viewModel)

        case .referral:
            ReferralFormView(viewModel: viewModel)

        case .meetup:
            MeetupFormView(viewModel: viewModel)

        case .dining:
            DiningFormView(viewModel: viewModel)

        case .event:
            EventFormView(viewModel: viewModel)

        case .service:
            ServiceFormView(viewModel: viewModel)

        case .merchant:
            MerchantFormView(viewModel: viewModel)

        case .coupon:
            CouponFormView(viewModel: viewModel)

        case .warning:
            WarningFormView(viewModel: viewModel)

        case .poll:
            PollFormView(viewModel: viewModel)

        case .anonymous:
            AnonymousFormView(viewModel: viewModel)
        }
    }
}
