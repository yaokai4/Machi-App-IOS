import SwiftUI

/// Display metadata + per-type form policy for `ContentType`. Centralised
/// so every view (picker, card, composer header, profile filters) reads
/// from one place.
///
/// Adding a new content type:
/// 1. Add the case to `ContentType` in DomainEnums.swift.
/// 2. Add a `Spec` entry below.
/// 3. (Optional) implement a typed form in Views/Compose/Forms/ and
///    return `hasTypedForm = true` so the composer routes to it.
/// 4. Mirror the addition in `web/server.py` (CONTENT_TYPES /
///    CONTENT_ATTR_SCHEMAS).
enum ContentTypeRegistry {
    struct Spec {
        /// Localization key for the displayed name. Resolved through
        /// `L(...)` so the picker / cards / composer all respect the
        /// in-app language.
        let titleKey: String
        /// SF Symbol used in the picker grid and on the card chip.
        let icon: String
        /// Accent tint. Picked from the system palette so the look
        /// stays consistent across light/dark and never needs new
        /// assets.
        let tint: Color
        /// Free-form one-liner shown under the icon in the picker.
        let subtitleKey: String
        /// When false, the composer falls back to the generic
        /// content-only form (text + media + tags). Setting this to
        /// true means there's a dedicated form in
        /// Views/Compose/Forms/<Type>FormView.swift that owns the
        /// per-type fields.
        let hasTypedForm: Bool
    }

    // Calmer palette — earlier "news = red" / "rant = pink" /
    // "dining = red" made every feed look like a warning page. We
    // now reserve red strictly for safety/warning content and use
    // muted blues / teals / oranges for the everyday types so cards
    // read as content-first rather than label-first.
    static let specs: [ContentType: Spec] = [
        .dynamic:    .init(titleKey: "ct_dynamic",   icon: "text.bubble",          tint: .blue,     subtitleKey: "ct_dynamic_sub",   hasTypedForm: false),
        .image_post: .init(titleKey: "ct_image",     icon: "photo.on.rectangle",   tint: .indigo,   subtitleKey: "ct_image_sub",     hasTypedForm: true),
        .long_post:  .init(titleKey: "ct_long",      icon: "doc.text",             tint: .gray,     subtitleKey: "ct_long_sub",      hasTypedForm: true),
        .news:       .init(titleKey: "ct_news",      icon: "newspaper",            tint: .blue,     subtitleKey: "ct_news_sub",      hasTypedForm: true),
        .local_info: .init(titleKey: "ct_localinfo", icon: "megaphone",            tint: .cyan,     subtitleKey: "ct_localinfo_sub", hasTypedForm: true),
        .guide:      .init(titleKey: "ct_guide",     icon: "book",                 tint: .teal,     subtitleKey: "ct_guide_sub",     hasTypedForm: true),
        .question:   .init(titleKey: "ct_question",  icon: "questionmark.bubble",  tint: .purple,   subtitleKey: "ct_question_sub",  hasTypedForm: true),
        .rant:       .init(titleKey: "ct_rant",      icon: "speaker.wave.2",       tint: .indigo,   subtitleKey: "ct_rant_sub",      hasTypedForm: true),
        .secondhand: .init(titleKey: "ct_secondhand",icon: "tag",                  tint: .green,    subtitleKey: "ct_secondhand_sub",hasTypedForm: true),
        .housing:    .init(titleKey: "ct_housing",   icon: "house",                tint: .blue,     subtitleKey: "ct_housing_sub",   hasTypedForm: true),
        .roommate:   .init(titleKey: "ct_roommate",  icon: "person.2",             tint: .cyan,     subtitleKey: "ct_roommate_sub",  hasTypedForm: true),
        .job_seek:   .init(titleKey: "ct_jobseek",   icon: "briefcase",            tint: .mint,     subtitleKey: "ct_jobseek_sub",   hasTypedForm: true),
        .job_post:   .init(titleKey: "ct_jobpost",   icon: "building.2",           tint: .indigo,   subtitleKey: "ct_jobpost_sub",   hasTypedForm: true),
        .referral:   .init(titleKey: "ct_referral",  icon: "person.crop.circle.badge.checkmark", tint: .indigo, subtitleKey: "ct_referral_sub", hasTypedForm: true),
        .meetup:     .init(titleKey: "ct_meetup",    icon: "hand.wave",            tint: .orange,   subtitleKey: "ct_meetup_sub",    hasTypedForm: true),
        .dining:     .init(titleKey: "ct_dining",    icon: "fork.knife",           tint: .orange,   subtitleKey: "ct_dining_sub",    hasTypedForm: true),
        .event:      .init(titleKey: "ct_event",     icon: "calendar",             tint: .purple,   subtitleKey: "ct_event_sub",     hasTypedForm: true),
        .service:    .init(titleKey: "ct_service",   icon: "wrench.and.screwdriver", tint: .brown,  subtitleKey: "ct_service_sub",   hasTypedForm: true),
        .merchant:   .init(titleKey: "ct_merchant",  icon: "storefront",           tint: .teal,     subtitleKey: "ct_merchant_sub",  hasTypedForm: true),
        .coupon:     .init(titleKey: "ct_coupon",    icon: "ticket",               tint: .pink,     subtitleKey: "ct_coupon_sub",    hasTypedForm: true),
        // Red reserved for genuine warnings / safety content.
        .warning:    .init(titleKey: "ct_warning",   icon: "exclamationmark.shield",tint: .red,     subtitleKey: "ct_warning_sub",   hasTypedForm: true),
        .poll:       .init(titleKey: "ct_poll",      icon: "chart.bar",            tint: .blue,     subtitleKey: "ct_poll_sub",      hasTypedForm: true),
        .anonymous:  .init(titleKey: "ct_anonymous", icon: "eye.slash",            tint: .gray,     subtitleKey: "ct_anonymous_sub", hasTypedForm: true),
    ]

    static func spec(for type: ContentType) -> Spec {
        specs[type] ?? specs[.dynamic]!
    }

    /// Order used in the type picker. Roughly: write-first generic
    /// stuff → marketplace → social → information → utility. Tuned so
    /// the most-used types are above the fold on a 4-column grid.
    /// The compose "+" picker now offers only social / editorial post types.
    /// Marketplace & service listings (二手/租房/找室友/招聘/找工作/商家与服务/
    /// 优惠/内推) were moved out: they each have a dedicated publish flow
    /// (workbench) and a browse channel under 同城, so surfacing them here too
    /// was redundant and read as a conflicting second entry point.
    // First 9 are the everyday community actions (the picker's "常用"); the
    // rarer / overlapping ones (图文 long-post, 长文, 本地告示, 吐槽, 树洞, 内推)
    // fold under "更多" so the first screen reads as ~8 clear choices instead
    // of a wall of 15.
    static let pickerOrder: [ContentType] = [
        .dynamic, .question, .guide, .warning,
        .meetup, .dining, .event, .poll, .news,
        .image_post, .long_post, .local_info, .rant, .anonymous, .referral,
    ]

    /// Marketplace / service listing types — still fully creatable, but only
    /// from their dedicated 同城 channel "+" and the workbench, never the
    /// generic compose picker.
    static let cityListingTypes: [ContentType] = [
        .secondhand, .housing, .roommate, .job_post, .job_seek,
        .merchant, .service, .coupon,
    ]
}

extension ContentType {
    var spec: ContentTypeRegistry.Spec { ContentTypeRegistry.spec(for: self) }
    /// Whether the composer should route to a dedicated form for this
    /// type (instead of the generic content + media flow).
    var hasTypedForm: Bool { spec.hasTypedForm }

    /// Lightweight editorial types can still be published with only
    /// body text / media / topics. Marketplace and transactional types
    /// should fill their structured fields so cards and filters have
    /// meaningful metadata to display.
    var allowsGenericPayloadOnly: Bool {
        switch self {
        case .image_post, .long_post, .question, .rant, .anonymous:
            return true
        default:
            return false
        }
    }

    /// High-trust types that require an active Machi Verified membership
    /// to publish. Mirrors REQUIRES_VERIFIED_MEMBERSHIP in web/server.py —
    /// the server is authoritative (returns 403 MEMBERSHIP_REQUIRED); the
    /// composer only uses this to gate the UX. Ordinary content stays free.
    var requiresVerifiedMembership: Bool {
        switch self {
        case .job_post, .housing, .roommate, .service, .coupon, .merchant, .referral:
            return true
        default:
            return false
        }
    }
}
