import SwiftUI

struct ServiceFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_service", icon: "wrench.and.screwdriver") {
            TypedTextField("fld_service_type", text: viewModel.stringBinding(PostAttributeKeys.serviceType), isRequired: true)
            TypedTextField("fld_price_range", text: viewModel.stringBinding(PostAttributeKeys.priceRange))
            TypedTextField("fld_contact_method", text: viewModel.stringBinding(PostAttributeKeys.contactMethod))
            TypedTextField("fld_merchant_id", text: viewModel.stringBinding(PostAttributeKeys.merchantId))
            TypedTextField("fld_verified_status", text: viewModel.stringBinding(PostAttributeKeys.verifiedStatus))
        }
    }
}

struct MerchantFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_merchant", icon: "storefront") {
            TypedTextField("fld_merchant_name", text: viewModel.stringBinding(PostAttributeKeys.merchantName), isRequired: true)
            TypedTextField("fld_merchant_type", text: viewModel.stringBinding(PostAttributeKeys.merchantType))
            TypedTextField("fld_address", text: viewModel.stringBinding(PostAttributeKeys.address), axis: .vertical)
            TypedTextField("fld_opening_hours", text: viewModel.stringBinding(PostAttributeKeys.openingHours))
            TypedTextField("fld_contact_method", text: viewModel.stringBinding(PostAttributeKeys.contactMethod))
            TypedTextField("fld_verified_status", text: viewModel.stringBinding(PostAttributeKeys.verifiedStatus))
            TypedTextField("fld_rating", text: viewModel.doubleBinding(PostAttributeKeys.rating), keyboard: .decimalPad)
        }
    }
}

struct CouponFormView: View {
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_coupon", icon: "ticket") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedTextField("fld_merchant_id", text: viewModel.stringBinding(PostAttributeKeys.merchantId))
            TypedTextField("fld_discount_info", text: viewModel.stringBinding(PostAttributeKeys.discountInfo), isRequired: true)
            TypedTextField("fld_valid_until", text: viewModel.stringBinding(PostAttributeKeys.validUntil))
            TypedTextField("fld_usage_rules", text: viewModel.stringBinding(PostAttributeKeys.usageRules), axis: .vertical)
        }
    }
}

struct WarningFormView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var viewModel: ComposePostViewModel

    var body: some View {
        TypedFormSection(titleKey: "ct_warning", icon: "exclamationmark.shield") {
            TypedTextField("fld_title", text: viewModel.stringBinding(PostAttributeKeys.title), isRequired: true)
            TypedTextField("fld_category", text: viewModel.stringBinding(PostAttributeKeys.category))
            TypedTextField("fld_description", text: viewModel.stringBinding(PostAttributeKeys.description), axis: .vertical)
            TypedTextField("fld_evidence_images", text: viewModel.stringBinding(PostAttributeKeys.evidenceImages), axis: .vertical)
            Toggle(isOn: viewModel.boolBinding(PostAttributeKeys.anonymous)) {
                Text(L("fld_anonymous", language))
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)
            TypedChoiceRow(
                titleKey: "fld_review_status",
                selection: viewModel.stringBinding(PostAttributeKeys.reviewStatus),
                options: [
                    ("under_review", "status_under_review"),
                    ("active", "status_active"),
                ]
            )
        }
        .onAppear {
            viewModel.seedFormDefault(PostAttributeKeys.reviewStatus, "under_review")
            viewModel.seedFormDefault(PostAttributeKeys.anonymous, true)
        }
    }
}
