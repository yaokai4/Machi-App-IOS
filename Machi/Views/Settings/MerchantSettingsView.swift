import SwiftUI
import UniformTypeIdentifiers

struct MerchantSettingsView: View {
    @Environment(\.appLanguage) private var language
    let currentUser: UserEntity

    @State private var business: KaiXBusinessProfileDTO?
    @State private var dashboard: KaiXBusinessDashboardDTO?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isUploading = false
    @State private var isImporterPresented = false
    @State private var isRegionPickerPresented = false
    @State private var message: String?
    @State private var pendingUploadedFileIds: [String] = []
    @State private var deletingDocumentId: String?

    @State private var businessName = ""
    @State private var businessType = "生活开通"
    @State private var legalName = ""
    @State private var representativeName = ""
    @State private var registrationNumber = ""
    @State private var countryCode = "jp"
    @State private var citySlug = "tokyo"
    @State private var phone = ""
    @State private var email = ""
    @State private var website = ""
    @State private var address = ""
    @State private var postalCode = ""
    @State private var contactMethod = ""
    @State private var serviceDescription = ""
    @State private var applicationNote = ""
    @State private var selectedCategories: Set<String> = ["生活开通"]

    private let businessTypes = ["餐厅", "旅行票务", "接送交通", "翻译手续", "搬家清洁", "生活开通", "美容健康"]
    private let serviceCategories = KXListingCopy.serviceCreateCategories

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                hero
                dashboardCard
                applicationForm
                documentSection
                reviewNoteSection
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, KXSpacing.md)
            .kxTabBarSafeBottomPadding()
        }
        .navigationTitle(L("merchantServiceConsoleTitle", language))
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            Task { await handleFileImport(result) }
        }
        .sheet(isPresented: $isRegionPickerPresented) {
            RegionPickerView(initialCountry: countryCode, allowsAnyCountry: true) { region in
                countryCode = region.countryCode
                citySlug = region.cityCode
            }
        }
    }

    private var status: String {
        business?.verification_status ?? (currentUser.merchantVerified ? "verified" : (currentUser.isMerchant ? "pending" : "not_started"))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: statusIcon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        LinearGradient(colors: [statusTint.opacity(0.92), statusTint.opacity(0.64)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: statusTint.opacity(0.32), radius: 7, y: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(business?.business_name.isEmpty == false ? business?.business_name ?? L("merchantServiceApplyTitle", language) : L("merchantServiceApplyTitle", language))
                        .font(.title3.weight(.bold))
                    Text(statusLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusTint)
                }
                Spacer()
            }
            Text(L("merchantServiceConsoleSubtitle", language))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            if let message {
                HStack(spacing: 6) {
                    Image(systemName: messageIsPositive ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.footnote.weight(.bold))
                    Text(message)
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(messageIsPositive ? Color.green : KXColor.heat)
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((messageIsPositive ? Color.green : KXColor.heat).opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(KXSpacing.lg)
        .kxGlassSurface(radius: KXRadius.hero, elevated: true)
    }

    private var messageIsPositive: Bool {
        guard let message else { return false }
        let knownPositiveMessages = [
            L("merchantSubmittedMessage", language),
            L("merchantSavedMessage", language),
            L("merchantDocumentWithdrawn", language),
        ]
        if knownPositiveMessages.contains(message) { return true }
        if message.hasPrefix("已") || message.contains("成功") { return true }
        return message.localizedCaseInsensitiveContains("uploaded")
            || message.localizedCaseInsensitiveContains("saved")
            || message.localizedCaseInsensitiveContains("submitted")
            || message.localizedCaseInsensitiveContains("withdrawn")
            || message.contains("アップロード")
            || message.contains("保存")
            || message.contains("送信")
            || message.contains("取り下げ")
    }

    private var dashboardCard: some View {
        SettingsSectionCard(title: L("merchantDashboard", language)) {
            if isLoading {
                HStack(spacing: 10) {
                    KXSpinner(size: 18, lineWidth: 2.4)
                    Text(L("merchantProfileLoading", language))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MerchantMetricTile(title: L("merchantMetricAllListings", language), value: dashboard?.metrics.listings ?? business?.listing_count ?? 0, icon: "square.grid.2x2.fill", tint: .blue)
                    MerchantMetricTile(title: L("merchantMetricPublished", language), value: dashboard?.metrics.published ?? business?.published_listing_count ?? 0, icon: "checkmark.seal.fill", tint: .green)
                    MerchantMetricTile(title: L("merchantMetricInquiries", language), value: dashboard?.metrics.inquiries ?? business?.inquiry_count ?? 0, icon: "bubble.left.and.bubble.right.fill", tint: .orange)
                    MerchantMetricTile(title: L("merchantMetricNewInquiries", language), value: dashboard?.metrics.new_inquiries ?? 0, icon: "sparkles", tint: .purple)
                }
                .padding(KXSpacing.md)
            }
        }
    }

    /// The server stores merchant location as bare slugs ("jp" + "tokyo");
    /// province-based countries need a directory sweep to resolve them
    /// back to a displayable region.
    private var resolvedMerchantRegion: KaiXRegionDirectory.Region? {
        let country = countryCode.trimmed.lowercased()
        let city = citySlug.trimmed.lowercased()
        guard !country.isEmpty, !city.isEmpty else { return nil }
        if let direct = KaiXRegionDirectory.make(country: country, province: nil, city: city) {
            return direct
        }
        guard let spec = KaiXRegionDirectory.countries.first(where: { $0.code == country }), spec.hasProvinces else {
            return nil
        }
        for province in KaiXRegionDirectory.provinces(for: country) {
            if let region = KaiXRegionDirectory.make(country: country, province: province.code, city: city) {
                return region
            }
        }
        return nil
    }

    private var regionFieldLabel: String {
        if let region = resolvedMerchantRegion {
            return "\(region.countryEmoji) \(KaiXRegionDirectory.localizedShortLabel(region, language: language))"
        }
        if let country = KaiXRegionDirectory.countries.first(where: { $0.code == countryCode.trimmed.lowercased() }) {
            return citySlug.trimmed.isEmpty
                ? "\(country.emoji) \(KaiXRegionDirectory.localizedCountryName(country, language: language)) · \(L("merchantSelectCity", language))"
                : "\(country.emoji) \(KaiXRegionDirectory.localizedCountryName(country, language: language)) · \(citySlug)"
        }
        return citySlug.trimmed.isEmpty ? L("merchantSelectCity", language) : "\(countryCode) · \(citySlug)"
    }

    private var applicationForm: some View {
        SettingsSectionCard(title: L("merchantVerificationProfile", language)) {
            VStack(alignment: .leading, spacing: 14) {
                MerchantFormGroupHeader(icon: "storefront.fill", title: L("merchantBasicInfo", language), tint: .teal)
                MerchantField(icon: "building.2", title: L("merchantBusinessName", language), required: true, text: $businessName, placeholder: L("merchantBusinessNamePlaceholder", language))
                MerchantPickerField(icon: "tag", title: L("merchantBusinessType", language), required: true, selection: $businessType, values: businessTypes, labelForValue: businessTypeLabel)
                MerchantField(icon: "doc.text", title: L("merchantLegalName", language), required: true, text: $legalName, placeholder: L("merchantLegalNamePlaceholder", language))
                MerchantField(icon: "person.text.rectangle", title: L("merchantRepresentativeName", language), required: true, text: $representativeName, placeholder: L("merchantRepresentativeNamePlaceholder", language), capitalization: .words)
                MerchantField(icon: "number", title: L("merchantRegistrationNumber", language), text: $registrationNumber, placeholder: L("merchantRegistrationNumberPlaceholder", language))

                MerchantFormGroupHeader(icon: "mappin.and.ellipse", title: L("merchantContactLocation", language), tint: .blue)
                MerchantTapField(icon: "globe.asia.australia", title: L("merchantOperatingCity", language), required: true, valueLabel: regionFieldLabel) {
                    isRegionPickerPresented = true
                }
                MerchantField(icon: "phone", title: L("merchantPhone", language), required: true, text: $phone, placeholder: "+81 90...", keyboard: .phonePad)
                MerchantField(icon: "envelope", title: L("merchantEmail", language), text: $email, placeholder: "business@example.com", keyboard: .emailAddress)
                MerchantField(icon: "link", title: L("merchantWebsite", language), text: $website, placeholder: "https://...", keyboard: .URL)
                MerchantField(icon: "location", title: L("merchantAddress", language), required: true, text: $address, placeholder: L("merchantAddressPlaceholder", language))
                MerchantField(icon: "signpost.right", title: L("merchantPostalCode", language), text: $postalCode, placeholder: "160-0022", keyboard: .numbersAndPunctuation)
                MerchantField(icon: "bubble.left.and.text.bubble.right", title: L("merchantPublicContact", language), text: $contactMethod, placeholder: L("merchantPublicContactPlaceholder", language))

                MerchantFormGroupHeader(icon: "sparkles", title: L("merchantServiceContent", language), tint: .orange)
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    MerchantFieldTitle(title: L("merchantServiceCategories", language), required: true)
                    FlowTags(values: serviceCategories, selected: $selectedCategories, labelForValue: categoryLabel)
                }
                MerchantTextEditor(icon: "text.alignleft", title: L("merchantServiceIntro", language), required: true, text: $serviceDescription, placeholder: L("merchantServiceIntroPlaceholder", language), countLabel: characterCountText)
                MerchantTextEditor(icon: "paperclip", title: L("merchantApplicationNote", language), text: $applicationNote, placeholder: L("merchantApplicationNotePlaceholder", language), countLabel: characterCountText)

                VStack(spacing: 10) {
                    Button {
                        Task { await save(submit: true) }
                    } label: {
                        HStack(spacing: KXSpacing.sm) {
                            if isSaving {
                                KXSpinner(size: 16, lineWidth: 2.2)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(isSaving ? L("merchantSubmitting", language) : L("merchantSubmitReview", language))
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            LinearGradient(colors: [KXColor.accent, KXColor.accent.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .shadow(color: KXColor.accent.opacity(0.30), radius: 8, y: 4)
                    }
                    .buttonStyle(KXPressableStyle())
                    .disabled(isSaving || isUploading)

                    Button {
                        Task { await save(submit: false) }
                    } label: {
                        Label(isSaving ? L("saving", language) : L("saveProfileOnly", language), systemImage: "tray.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KXColor.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(KXColor.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(KXColor.accent.opacity(0.24), lineWidth: 0.8))
                    }
                    .buttonStyle(KXPressableStyle())
                    .disabled(isSaving || isUploading)
                }
                .padding(.top, KXSpacing.xxs)
            }
            .padding(14)
        }
    }

    private var documentSection: some View {
        SettingsSectionCard(title: L("merchantDocuments", language)) {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                Text(L("merchantDocsHelp", language))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                Button {
                    isImporterPresented = true
                } label: {
                    HStack(spacing: KXSpacing.sm) {
                        if isUploading {
                            KXSpinner(size: 16, lineWidth: 2.2)
                        } else {
                            Image(systemName: "doc.badge.plus")
                        }
                        Text(isUploading ? L("uploading", language) : L("uploadDocuments", language))
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(KXColor.accent.opacity(0.07))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(KXColor.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.1, dash: [5, 4]))
                    }
                }
                .buttonStyle(KXPressableStyle())
                .disabled(isUploading || isSaving)

                let docs = business?.documents ?? []
                if docs.isEmpty {
                    Text(L("merchantDocsEmpty", language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: KXSpacing.sm) {
                        ForEach(docs) { doc in
                            HStack(spacing: 10) {
                                Image(systemName: doc.contentType == "application/pdf" ? "doc.richtext.fill" : "photo.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                                    Text(doc.documentType ?? L("merchantDocumentDefault", language))
                                        .font(.subheadline.weight(.bold))
                                    Text("\(formatBytes(doc.fileSize ?? 0)) · \(doc.status ?? doc.documentStatus ?? "submitted")")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(L("privateBadge", language))
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, KXSpacing.sm)
                                    .frame(height: 22)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                if let documentId = doc.documentId {
                                    Button(role: .destructive) {
                                        Task { await deleteDocument(documentId) }
                                    } label: {
                                        if deletingDocumentId == documentId {
                                            KXSpinner(size: 14, lineWidth: 2)
                                        } else {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(deletingDocumentId != nil || isSaving || isUploading)
                                    .accessibilityLabel(L("removeMerchantDocument", language))
                                }
                            }
                            .padding(10)
                            .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                        }
                    }
                }
            }
            .padding(KXSpacing.md)
        }
    }

    @ViewBuilder
    private var reviewNoteSection: some View {
        if let note = business?.review_note, !note.isEmpty {
            SettingsSectionCard(title: L("merchantReviewNoteTitle", language)) {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(KXSpacing.md)
            }
        }
    }

    private var statusIcon: String {
        switch status {
        case "verified": "checkmark.seal.fill"
        case "pending": "hourglass"
        case "needs_review": "exclamationmark.triangle.fill"
        case "rejected": "xmark.seal.fill"
        case "suspended": "pause.circle.fill"
        default: "storefront.fill"
        }
    }

    private var statusTint: Color {
        switch status {
        case "verified": .green
        case "pending": .orange
        case "needs_review": .blue
        case "rejected": .red
        case "suspended": .secondary
        default: KXColor.accent
        }
    }

    private var statusLabel: String {
        switch status {
        case "verified": return L("merchantVerified", language)
        case "pending": return L("merchantStatusPendingLabel", language)
        case "needs_review": return L("merchantStatusNeedsReviewLabel", language)
        case "rejected": return L("merchantStatusRejectedLabel", language)
        case "suspended": return L("merchantStatusSuspendedLabel", language)
        case "draft": return L("merchantStatusDraftLabel", language)
        default: return L("merchantStatusNotStartedLabel", language)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await KaiXAPIClient.shared.businessProfile()
            applyBusiness(response.business)
            dashboard = try? await KaiXAPIClient.shared.businessDashboard()
        } catch {
            message = error.kaixUserMessage
        }
    }

    @MainActor
    private func applyBusiness(_ profile: KaiXBusinessProfileDTO?) {
        business = profile
        guard let profile else {
            businessName = businessName.isEmpty ? currentUser.displayName : businessName
            email = email.isEmpty ? currentUser.email : email
            return
        }
        businessName = profile.business_name
        businessType = profile.business_type.isEmpty ? "生活开通" : profile.business_type
        legalName = profile.legal_name ?? ""
        representativeName = profile.representative_name ?? ""
        registrationNumber = profile.registration_number ?? ""
        countryCode = profile.country_code ?? "jp"
        citySlug = profile.city_slug ?? "tokyo"
        phone = profile.phone ?? ""
        email = profile.email ?? currentUser.email
        website = profile.website ?? ""
        address = profile.address ?? ""
        postalCode = profile.postal_code ?? ""
        contactMethod = profile.contact_method ?? ""
        serviceDescription = profile.description ?? ""
        applicationNote = profile.application_note ?? ""
        selectedCategories = Set(profile.service_categories?.isEmpty == false ? profile.service_categories ?? [] : ["生活支持"])
    }

    @discardableResult
    private func save(submit: Bool, showMessage: Bool = true) async -> KaiXBusinessProfileDTO? {
        let validation = validationMessage(submit: submit)
        if let validation {
            message = validation
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await KaiXAPIClient.shared.saveBusinessApplication(payload(submit: submit))
            pendingUploadedFileIds.removeAll()
            applyBusiness(response.business)
            dashboard = try? await KaiXAPIClient.shared.businessDashboard()
            if showMessage {
                message = submit ? L("merchantSubmittedMessage", language) : L("merchantSavedMessage", language)
            }
            return response.business
        } catch {
            message = error.kaixUserMessage
            return nil
        }
    }

    private func payload(submit: Bool) -> KaiXBusinessApplicationPayload {
        KaiXBusinessApplicationPayload(
            business_name: businessName.trimmed,
            business_type: businessType.trimmed,
            legal_name: legalName.trimmed,
            representative_name: representativeName.trimmed,
            registration_number: registrationNumber.trimmed,
            country_code: countryCode.trimmed.lowercased(),
            city_slug: citySlug.trimmed.lowercased(),
            phone: phone.trimmed,
            email: email.trimmed,
            website: website.trimmed,
            address: address.trimmed,
            postal_code: postalCode.trimmed,
            contact_method: contactMethod.trimmed,
            description: serviceDescription.trimmed,
            application_note: applicationNote.trimmed,
            service_categories: Array(selectedCategories).sorted(),
            service_cities: [citySlug.trimmed.lowercased()].filter { !$0.isEmpty },
            uploadedFileIds: pendingUploadedFileIds,
            submit: submit
        )
    }

    private func validationMessage(submit: Bool) -> String? {
        if businessName.trimmed.isEmpty { return L("merchantValidationName", language) }
        guard submit else { return nil }
        var missing: [String] = []
        if businessType.trimmed.isEmpty { missing.append(L("merchantBusinessType", language)) }
        if legalName.trimmed.isEmpty { missing.append(L("merchantLegalName", language)) }
        if representativeName.trimmed.isEmpty { missing.append(L("merchantRepresentativeName", language)) }
        if countryCode.trimmed.isEmpty { missing.append(L("merchantMissingCountry", language)) }
        if citySlug.trimmed.isEmpty { missing.append(L("merchantMissingCity", language)) }
        if phone.trimmed.isEmpty && email.trimmed.isEmpty { missing.append(L("merchantMissingPhoneOrEmail", language)) }
        if address.trimmed.isEmpty { missing.append(L("merchantAddress", language)) }
        if serviceDescription.trimmed.isEmpty { missing.append(L("merchantServiceIntro", language)) }
        if selectedCategories.isEmpty { missing.append(L("merchantServiceCategories", language)) }
        let documentCount = business?.documents?.count ?? 0
        if documentCount + pendingUploadedFileIds.count <= 0 { missing.append(L("merchantDocuments", language)) }
        return missing.isEmpty ? nil : L("merchantValidationCompletePrefix", language) + missing.joined(separator: missingSeparator)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            let ensuredBusiness: KaiXBusinessProfileDTO?
            if let business {
                ensuredBusiness = business
            } else {
                ensuredBusiness = await save(submit: false, showMessage: false)
            }
            guard let businessId = ensuredBusiness?.id else {
                message = L("merchantUploadFirstSave", language)
                return
            }
            isUploading = true
            defer { isUploading = false }
            var uploadedIds: [String] = []
            for url in urls.prefix(10) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try await Task.detached(priority: .utility) {
                    try Data(contentsOf: url)
                }.value
                let mime = mimeType(for: url)
                let uploaded = try await KaiXAPIClient.shared.uploadFile(
                    data: data,
                    mime: mime,
                    fileName: url.lastPathComponent,
                    purpose: "business_verification_file",
                    entityType: "business",
                    entityId: businessId
                )
                uploadedIds.append(uploaded.file.id)
            }
            pendingUploadedFileIds.append(contentsOf: uploadedIds)
            _ = await save(submit: false, showMessage: false)
            message = String(format: L("merchantUploadedCount", language), uploadedIds.count)
        } catch {
            message = error.kaixUserMessage
        }
    }

    private func deleteDocument(_ documentId: String) async {
        deletingDocumentId = documentId
        defer { deletingDocumentId = nil }
        do {
            let response = try await KaiXAPIClient.shared.deleteBusinessDocument(documentId)
            pendingUploadedFileIds.removeAll()
            applyBusiness(response.business)
            dashboard = try? await KaiXAPIClient.shared.businessDashboard()
            message = L("merchantDocumentWithdrawn", language)
        } catch {
            message = error.kaixUserMessage
        }
    }

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        return url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg"
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes <= 0 { return L("fileSizeUnknown", language) }
        if bytes < 1_048_576 { return "\(max(1, bytes / 1024)) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }

    private func businessTypeLabel(_ value: String) -> String {
        if let section = KXListingCopy.serviceCreateSections.first(where: { $0.zh == value }) {
            return section.label(language)
        }
        return KXListingCopy.categoryLabel(value, language)
    }

    private func categoryLabel(_ value: String) -> String {
        KXListingCopy.categoryLabel(value, language)
    }

    private func characterCountText(_ count: Int) -> String {
        String(format: L("characterCountFormat", language), count)
    }

    private var missingSeparator: String {
        language == .en ? ", " : "、"
    }
}

private struct MerchantMetricTile: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text("\(value)")
                .font(.title3.weight(.black))
                .contentTransition(.numericText())
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KXSpacing.md)
        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Form building blocks

/// Mini group header that splits the long application form into
/// scannable sections (基本信息 / 联系与位置 / 服务内容).
private struct MerchantFormGroupHeader: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: KXRadius.xs, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.bold))
            Rectangle()
                .fill(KXColor.separator.opacity(0.7))
                .frame(height: 0.7)
        }
        .padding(.top, KXSpacing.xs)
    }
}

private struct MerchantFieldTitle: View {
    let title: String
    var required = false

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if required {
                Text("*")
                    .font(.caption.weight(.black))
                    .foregroundStyle(KXColor.heat)
            }
        }
    }
}

/// Single-line input with icon, required badge, focus halo and proper
/// keyboard type — replaces the bare `.roundedBorder` text fields.
private struct MerchantField: View {
    @Environment(\.appLanguage) private var language
    let icon: String
    let title: String
    var required = false
    @Binding var text: String
    let placeholder: String
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MerchantFieldTitle(title: title, required: required)
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(focused ? KXColor.accent : .secondary)
                    .frame(width: 20)
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.subheadline.weight(.medium))
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .focused($focused)
                if !text.isEmpty && focused {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(KXListingCopy.pickText(language, "清空", "クリア", "Clear"))
                }
            }
            .padding(.horizontal, KXSpacing.md)
            .padding(.vertical, 11)
            .background(KXColor.softBackground.opacity(focused ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(focused ? KXColor.accent.opacity(0.65) : KXColor.separator.opacity(0.55), lineWidth: focused ? 1.2 : 0.7)
            }
            .animation(.easeOut(duration: 0.16), value: focused)
        }
    }
}

/// Tappable field (same silhouette as MerchantField) that opens a
/// picker — used for the country/city pair so merchants never have to
/// type raw slugs like "jp / tokyo" again.
private struct MerchantTapField: View {
    let icon: String
    let title: String
    var required = false
    let valueLabel: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MerchantFieldTitle(title: title, required: required)
            Button(action: action) {
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(valueLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, KXSpacing.md)
                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(KXColor.separator.opacity(0.55), lineWidth: 0.7)
                }
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(KXPressableStyle(scale: 0.985))
        }
    }
}

private struct MerchantPickerField: View {
    let icon: String
    let title: String
    var required = false
    @Binding var selection: String
    let values: [String]
    var labelForValue: (String) -> String = { $0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MerchantFieldTitle(title: title, required: required)
            Menu {
                ForEach(values, id: \.self) { value in
                    let label = labelForValue(value)
                    Button {
                        selection = value
                    } label: {
                        if selection == value {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(labelForValue(selection))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, KXSpacing.md)
                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(KXColor.separator.opacity(0.55), lineWidth: 0.7)
                }
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }
}

private struct MerchantTextEditor: View {
    let icon: String
    let title: String
    var required = false
    @Binding var text: String
    let placeholder: String
    var countLabel: (Int) -> String = { "\($0) 字" }
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                MerchantFieldTitle(title: title, required: required)
                Spacer()
                if !text.isEmpty {
                    Text(countLabel(text.count))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 10)
                }
                TextEditor(text: $text)
                    .font(.subheadline)
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, KXSpacing.xs)
                    .padding(.vertical, KXSpacing.xxs)
                    .focused($focused)
            }
            .background(KXColor.softBackground.opacity(focused ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(focused ? KXColor.accent.opacity(0.65) : KXColor.separator.opacity(0.55), lineWidth: focused ? 1.2 : 0.7)
            }
            .animation(.easeOut(duration: 0.16), value: focused)
        }
    }
}

private struct FlowTags: View {
    let values: [String]
    @Binding var selected: Set<String>
    var labelForValue: (String) -> String = { $0 }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: KXSpacing.sm)], spacing: KXSpacing.sm) {
            ForEach(values, id: \.self) { value in
                let isOn = selected.contains(value)
                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        if isOn {
                            selected.remove(value)
                        } else {
                            selected.insert(value)
                        }
                    }
                } label: {
                    HStack(spacing: KXSpacing.xs) {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.black))
                        }
                        Text(labelForValue(value))
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .foregroundStyle(isOn ? Color.white : .secondary)
                    .background(isOn ? AnyShapeStyle(KXColor.accent) : AnyShapeStyle(KXColor.softBackground), in: Capsule())
                    .overlay(Capsule().stroke(isOn ? Color.clear : KXColor.separator.opacity(0.6), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
