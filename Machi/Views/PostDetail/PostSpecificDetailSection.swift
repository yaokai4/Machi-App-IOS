import SwiftData
import SwiftUI

/// Per-content-type structured detail block. Renders below the
/// universal PostCardView in PostDetailView so that secondhand /
/// housing / job / meetup / event / merchant / coupon posts surface
/// every field the composer captured — not just the body text.
///
/// Card-style with labeled rows. Hides itself entirely for the
/// "generic" content types (dynamic / image_post / long_post / rant /
/// anonymous) where the body and media already say it all.
struct PostSpecificDetailSection: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: KXRouter
    @EnvironmentObject private var toastManager: ToastManager
    let post: PostEntity
    let currentUser: UserEntity?
    @State private var openingDM = false
    // 約局 RSVP state (meetup / dining / event)
    @State private var meetupGoing = 0
    @State private var meetupJoined = false
    @State private var meetupLoaded = false
    @State private var meetupBusy = false

    var body: some View {
        let rows = detailRows
        if rows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: post.contentType.spec.icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(post.contentType == .warning ? KXColor.heat : post.contentType.spec.tint)
                    Text(L(post.contentType.spec.titleKey, language))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    statusBadge
                    Spacer(minLength: 0)
                }
                ForEach(rows) { row in
                    DetailRow(row: row)
                }
                if isMeetupRSVP {
                    meetupJoinBar
                }
                if showContactBar {
                    contactBar
                }
            }
            .padding(14)
            .kxGlassSurface(radius: KXRadius.lg)
            .task {
                guard isMeetupRSVP, !meetupLoaded else { return }
                meetupLoaded = true
                if let res = try? await KaiXAPIClient.shared.meetupParticipants(post.id) {
                    meetupGoing = res.count
                    if let me = currentUser { meetupJoined = res.ids.contains(me.id) }
                }
            }
        }
    }

    // MARK: - 約局 RSVP

    private var isMeetupRSVP: Bool {
        switch post.contentType {
        case .meetup, .dining, .event: return true
        default: return false
        }
    }

    private var meetupCapacity: Int {
        Int(attr(PostAttributeKeys.peopleLimit)) ?? Int(attr(PostAttributeKeys.capacity)) ?? 0
    }

    private var meetupJoinBar: some View {
        let full = meetupCapacity > 0 && meetupGoing >= meetupCapacity && !meetupJoined
        return HStack(spacing: 10) {
            Label(
                meetupCapacity > 0 ? "\(meetupGoing) / \(meetupCapacity) 人已报名" : "\(meetupGoing) 人已报名",
                systemImage: "person.2.fill"
            )
            .font(.subheadline.weight(.bold))
            .foregroundStyle(KXColor.accent)
            Spacer(minLength: 0)
            if currentUser?.id == post.authorId {
                Text("你发起的局").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await toggleMeetupJoin() }
                } label: {
                    HStack(spacing: 5) {
                        if meetupBusy {
                            KXSpinner(size: 14, lineWidth: 2, tint: meetupJoined ? KXColor.accent : .white)
                        } else if meetupJoined {
                            Image(systemName: "checkmark").font(.caption.weight(.bold))
                        }
                        Text(meetupJoined ? "已报名" : (full ? "名额已满" : "报名参加"))
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .foregroundStyle(meetupJoined ? KXColor.accent : .white)
                    .background(meetupJoined ? KXColor.accentSoft : KXColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(meetupBusy || (full && !meetupJoined))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(KXColor.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @MainActor
    private func toggleMeetupJoin() async {
        guard let me = currentUser else {
            toastManager.show(.custom(
                title: KXListingCopy.pickText(language, "请先登录", "ログインしてください", "Please sign in"),
                message: KXListingCopy.pickText(language, "登录后才能报名", "ログインすると参加できます", "Sign in to join"),
                systemImage: "person.crop.circle.badge.exclamationmark", tint: KXColor.accent, technicalDetails: nil,
            ), duration: 2.5)
            return
        }
        _ = me
        meetupBusy = true
        defer { meetupBusy = false }
        do {
            let updated = try await KaiXAPIClient.shared.setMeetupJoin(post.id, !meetupJoined)
            meetupGoing = updated.meetupGoing ?? meetupGoing
            meetupJoined = updated.meetupJoined ?? !meetupJoined
            GuideHaptics.success()
        } catch {
            toastManager.show(.requestFailed(
                message: KXListingCopy.pickText(language, "报名失败（可能名额已满）", "参加できませんでした（満員の可能性）", "Could not join (may be full)"),
                technicalDetails: error.localizedDescription,
            ), duration: 2.5)
        }
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        let status = post.stringAttribute(PostAttributeKeys.status) ?? ""
        if !status.isEmpty {
            Text(L("status_\(status)", language))
                .font(.caption2.weight(.bold))
                .foregroundStyle(statusColor(for: status))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(statusColor(for: status).opacity(0.12), in: Capsule())
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "available": return .green
        case "reserved": return .orange
        case "sold", "rented": return .gray
        case "under_review": return .orange
        case "active": return KXColor.accent
        default: return .secondary
        }
    }

    // MARK: - Contact bar

    /// Whether this content type warrants a footer with private message
    /// / report / inquiry buttons. Most marketplace / social listings do.
    private var showContactBar: Bool {
        switch post.contentType {
        case .secondhand, .housing, .roommate, .job_post, .job_seek, .referral,
             .meetup, .dining, .event, .service, .merchant, .coupon:
            return true
        default:
            return false
        }
    }

    private var contactBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await openConversation() }
            } label: {
                HStack(spacing: 6) {
                    if openingDM {
                        KXSpinner(size: 16, lineWidth: 2, tint: .white)
                    } else {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(openingDM ? L("loading", language) : L("contactSeller", language))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .disabled(openingDM || currentUser?.id == post.authorId)
            .foregroundStyle(.white)
            .background(KXColor.accent, in: Capsule())

            Button {
                toastManager.show(.custom(
                    title: L("reportRecorded", language),
                    message: "",
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    technicalDetails: nil,
                ), duration: 2)
            } label: {
                Image(systemName: "flag")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 38)
                    .kxGlassCapsule()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("举报")
        }
        .padding(.top, 4)
    }

    // MARK: - DM

    /// Open (or create) the conversation with the post's author and
    /// route to ConversationView. Falls back to a toast if the user is
    /// signed-out or the repository call fails.
    @MainActor
    private func openConversation() async {
        guard let me = currentUser else {
            toastManager.show(.custom(
                title: KXListingCopy.pickText(language, "请先登录", "ログインしてください", "Please sign in"),
                message: KXListingCopy.pickText(language, "登录后才能发起私信", "ログインするとメッセージを送れます", "Sign in to start a private message"),
                systemImage: "person.crop.circle.badge.exclamationmark",
                tint: KXColor.accent,
                technicalDetails: nil,
            ), duration: 2.5)
            return
        }
        guard post.authorId != me.id else { return }
        openingDM = true
        defer { openingDM = false }
        do {
            let repo = MessageRepository(context: modelContext)
            let thread = try await repo.getOrCreateThread(currentUserId: me.id, peerUserId: post.authorId)
            router.open(.conversation(conversationId: thread.id))
        } catch {
            toastManager.show(.requestFailed(
                message: KXListingCopy.pickText(language, "无法打开私信", "メッセージを開けませんでした", "Could not open messages"),
                technicalDetails: error.localizedDescription,
            ), duration: 2.5)
        }
    }

    // MARK: - Detail rows

    private var detailRows: [DetailRowSpec] {
        switch post.contentType {
        case .secondhand:
            return [
                ("fld_price", priceLabel),
                ("fld_currency", attr(PostAttributeKeys.currency)),
                ("fld_condition", attr(PostAttributeKeys.condition)),
                ("fld_trade_method", attr(PostAttributeKeys.tradeMethod)),
                ("fld_area", attr(PostAttributeKeys.area, fallback: regionLabel)),
            ].toSpecs()

        case .housing:
            return [
                ("fld_rent", attr(PostAttributeKeys.rent).isEmpty ? "" : "\(attr(PostAttributeKeys.currency)) \(attr(PostAttributeKeys.rent))".trimmingCharacters(in: .whitespaces)),
                ("fld_room_type", attr(PostAttributeKeys.roomType)),
                ("fld_area", attr(PostAttributeKeys.area, fallback: regionLabel)),
                ("fld_nearest_station", attr(PostAttributeKeys.nearestStation)),
                ("fld_deposit", attr(PostAttributeKeys.deposit)),
                ("fld_key_money", attr(PostAttributeKeys.keyMoney)),
                ("fld_move_in_date", attr(PostAttributeKeys.moveInDate)),
                ("fld_contact_method", attr(PostAttributeKeys.contactMethod)),
            ].toSpecs()

        case .roommate:
            return [
                ("fld_rent_range", attr(PostAttributeKeys.rentRange)),
                ("fld_area", attr(PostAttributeKeys.area, fallback: regionLabel)),
                ("fld_move_in_date", attr(PostAttributeKeys.moveInDate)),
                ("fld_lifestyle_tags", attr(PostAttributeKeys.lifestyleTags)),
                ("fld_requirements", attr(PostAttributeKeys.requirements)),
                ("fld_contact_method", attr(PostAttributeKeys.contactMethod)),
            ].toSpecs()

        case .job_post, .referral:
            return [
                ("fld_job_title", attr(PostAttributeKeys.jobTitle)),
                ("fld_company_name", attr(PostAttributeKeys.companyName)),
                ("fld_salary", attr(PostAttributeKeys.salary)),
                ("fld_job_type", jobTypeLabel),
                ("fld_language_req", attr(PostAttributeKeys.languageRequirement)),
                ("fld_visa_req", attr(PostAttributeKeys.visaRequirement)),
                ("fld_work_location", attr(PostAttributeKeys.workLocation, fallback: regionLabel)),
                ("fld_contact_method", attr(PostAttributeKeys.contactMethod)),
            ].toSpecs()

        case .job_seek:
            return [
                ("fld_desired_job", attr(PostAttributeKeys.desiredJob)),
                ("fld_skills", attr(PostAttributeKeys.skills)),
                ("fld_languages", attr(PostAttributeKeys.languages)),
                ("fld_visa_status", attr(PostAttributeKeys.visaStatus)),
                ("fld_availability", attr(PostAttributeKeys.availability)),
                ("fld_expected_salary", attr(PostAttributeKeys.expectedSalary)),
                ("fld_contact_method", attr(PostAttributeKeys.contactMethod)),
            ].toSpecs()

        case .meetup:
            return [
                ("fld_meetup_type", attr(PostAttributeKeys.meetupType)),
                ("fld_meetup_time", attr(PostAttributeKeys.meetupTime)),
                ("fld_location", attr(PostAttributeKeys.location, fallback: regionLabel)),
                ("fld_people_limit", attr(PostAttributeKeys.peopleLimit)),
                ("fld_budget", attr(PostAttributeKeys.budget)),
                ("safetyNotice", attr(PostAttributeKeys.safetyNotice)),
            ].toSpecs()

        case .dining:
            return [
                ("fld_restaurant_or_area", attr(PostAttributeKeys.restaurantOrArea, fallback: regionLabel)),
                ("fld_meetup_time", attr(PostAttributeKeys.meetupTime)),
                ("fld_people_limit", attr(PostAttributeKeys.peopleLimit)),
                ("fld_budget", attr(PostAttributeKeys.budget)),
            ].toSpecs()

        case .event:
            return [
                ("fld_event_time", attr(PostAttributeKeys.eventTime)),
                ("fld_location", attr(PostAttributeKeys.location, fallback: regionLabel)),
                ("fld_fee", attr(PostAttributeKeys.fee)),
                ("fld_capacity", attr(PostAttributeKeys.capacity)),
                ("fld_registration", attr(PostAttributeKeys.registrationMethod)),
            ].toSpecs()

        case .guide:
            return [
                ("fld_summary", attr(PostAttributeKeys.summary)),
                ("fld_last_updated", attr(PostAttributeKeys.lastUpdatedAt)),
                ("bookmarks", "\(post.bookmarkCount)"),
            ].toSpecs()

        case .news, .local_info:
            return [
                ("fld_source", attr(PostAttributeKeys.source, fallback: "Machi")),
                ("fld_event_time", attr(PostAttributeKeys.eventTime, fallback: post.createdAt.formatted(date: .abbreviated, time: .shortened))),
                ("fld_location", attr(PostAttributeKeys.location, fallback: regionLabel)),
                ("fld_external_url", attr(PostAttributeKeys.externalURL)),
                ("fld_summary", attr(PostAttributeKeys.summary)),
            ].toSpecs()

        case .merchant:
            return [
                ("fld_merchant_name", attr(PostAttributeKeys.merchantName)),
                ("fld_merchant_type", attr(PostAttributeKeys.merchantType)),
                ("fld_address", attr(PostAttributeKeys.address, fallback: regionLabel)),
                ("fld_opening_hours", attr(PostAttributeKeys.openingHours)),
                ("fld_rating", attr(PostAttributeKeys.rating)),
                ("fld_contact_method", attr(PostAttributeKeys.contactMethod)),
                ("fld_verified_status", attr(PostAttributeKeys.verifiedStatus)),
            ].toSpecs()

        case .service:
            return [
                ("fld_service_type", attr(PostAttributeKeys.serviceType)),
                ("fld_price_range", attr(PostAttributeKeys.priceRange)),
                ("fld_contact_method", attr(PostAttributeKeys.contactMethod)),
                ("fld_verified_status", attr(PostAttributeKeys.verifiedStatus)),
            ].toSpecs()

        case .coupon:
            return [
                ("fld_discount_info", attr(PostAttributeKeys.discountInfo)),
                ("fld_valid_until", attr(PostAttributeKeys.validUntil)),
                ("fld_usage_rules", attr(PostAttributeKeys.usageRules)),
                ("fld_merchant_id", attr(PostAttributeKeys.merchantId)),
            ].toSpecs()

        case .warning:
            return [
                ("fld_category", attr(PostAttributeKeys.category)),
                ("fld_description", attr(PostAttributeKeys.description)),
                ("fld_review_status", attr(PostAttributeKeys.reviewStatus)),
            ].toSpecs()

        case .question:
            return [
                ("fld_category", attr(PostAttributeKeys.category)),
            ].toSpecs()

        case .poll:
            return [
                ("fld_poll_options", attr(PostAttributeKeys.options)),
                ("fld_expires_at", attr(PostAttributeKeys.expiresAt)),
            ].toSpecs()

        default:
            return []
        }
    }

    // MARK: - Helpers

    private var priceLabel: String {
        let p = attr(PostAttributeKeys.price)
        let c = attr(PostAttributeKeys.currency)
        guard !p.isEmpty else { return "" }
        return c.isEmpty ? p : "\(c) \(p)"
    }

    private var jobTypeLabel: String {
        let value = attr(PostAttributeKeys.jobType)
        guard !value.isEmpty else { return "" }
        let key = "jt_\(value)"
        let resolved = L(key, language)
        return resolved == key ? value : resolved
    }

    private var regionLabel: String {
        if let region = KaiXRegionDirectory.resolve(regionCode: post.regionCode) {
            return region.displayName
        }
        let parts = [post.country, post.province, post.city].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func attr(_ key: String, fallback: String = "") -> String {
        if let s = post.stringAttribute(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        if let d = post.doubleAttribute(key) {
            return d == d.rounded() ? "\(Int(d))" : String(format: "%.2f", d)
        }
        if let i = post.intAttribute(key) {
            return "\(i)"
        }
        return fallback
    }
}

private struct DetailRowSpec: Identifiable {
    let id = UUID()
    let labelKey: String
    let value: String
}

private extension Array where Element == (String, String) {
    /// Drop empty-value rows so the section doesn't show a wall of
    /// labels with nothing next to them.
    func toSpecs() -> [DetailRowSpec] {
        compactMap { (key, value) in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return DetailRowSpec(labelKey: key, value: trimmed)
        }
    }
}

private struct DetailRow: View {
    @Environment(\.appLanguage) private var language
    let row: DetailRowSpec

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(L(row.labelKey, language))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(row.value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
