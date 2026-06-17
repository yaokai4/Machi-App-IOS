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
    @State private var businessType = "生活服务"
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
    @State private var selectedCategories: Set<String> = ["生活服务"]

    private let businessTypes = ["餐厅美食", "咖啡甜品", "生活服务", "民宿 / 酒店", "景点票务", "旅行玩乐", "接送交通", "翻译手续", "搬家清洁", "生活开通", "美容健康", "宠物家庭", "房产服务", "招聘雇主"]
    private let serviceCategories = ["餐厅美食", "在线订座", "优惠预约", "民宿", "酒店", "温泉旅馆", "公寓式酒店", "短住公寓", "景点门票", "一日游", "本地向导", "机场接送", "车站接送", "包车", "行李协助", "材料翻译", "市役所陪同", "银行卡协助", "手机卡协助", "租房申请协助", "签证材料整理", "搬家", "退房清洁", "粗大垃圾协助", "行李搬运", "家具家电配送协助", "手机卡开通", "网络开通", "水电煤协助", "地址登记协助", "粗大垃圾预约", "生活跑腿", "美容美发", "美甲", "按摩", "皮肤管理", "体检/牙科预约协助", "宠物照看", "亲子摄影", "家政陪同"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                dashboardCard
                applicationForm
                documentSection
                reviewNoteSection
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 12)
            .kxTabBarSafeBottomPadding()
        }
        .navigationTitle("商家服务后台")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
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
                    Text(business?.business_name.isEmpty == false ? business?.business_name ?? "申请认证商家服务" : "申请认证商家服务")
                        .font(.title3.weight(.bold))
                    Text(statusLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusTint)
                }
                Spacer()
            }
            Text("覆盖餐饮预约、住宿旅行、票务行程、接送交通、手续翻译、搬家清洁、生活开通和美容健康等高频本地服务。提交后进入人工审核，Web 与 iOS 同步显示认证状态。")
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
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((messageIsPositive ? Color.green : KXColor.heat).opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .kxGlassSurface(radius: 24, elevated: true)
    }

    private var messageIsPositive: Bool {
        guard let message else { return false }
        return message.hasPrefix("已") || message.contains("成功")
    }

    private var dashboardCard: some View {
        SettingsSectionCard(title: "经营看板") {
            if isLoading {
                HStack(spacing: 10) {
                    KXSpinner(size: 18, lineWidth: 2.4)
                    Text("正在加载商家资料")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MerchantMetricTile(title: "全部发布", value: dashboard?.metrics.listings ?? business?.listing_count ?? 0, icon: "square.grid.2x2.fill", tint: .blue)
                    MerchantMetricTile(title: "展示中", value: dashboard?.metrics.published ?? business?.published_listing_count ?? 0, icon: "checkmark.seal.fill", tint: .green)
                    MerchantMetricTile(title: "全部线索", value: dashboard?.metrics.inquiries ?? business?.inquiry_count ?? 0, icon: "bubble.left.and.bubble.right.fill", tint: .orange)
                    MerchantMetricTile(title: "新增线索", value: dashboard?.metrics.new_inquiries ?? 0, icon: "sparkles", tint: .purple)
                }
                .padding(12)
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
                ? "\(country.emoji) \(KaiXRegionDirectory.localizedCountryName(country, language: language)) · 选择城市"
                : "\(country.emoji) \(KaiXRegionDirectory.localizedCountryName(country, language: language)) · \(citySlug)"
        }
        return citySlug.trimmed.isEmpty ? "选择经营城市" : "\(countryCode) · \(citySlug)"
    }

    private var applicationForm: some View {
        SettingsSectionCard(title: "认证资料") {
            VStack(alignment: .leading, spacing: 14) {
                MerchantFormGroupHeader(icon: "storefront.fill", title: "基本信息", tint: .teal)
                MerchantField(icon: "building.2", title: "商家/品牌名称", required: true, text: $businessName, placeholder: "Machi Coffee / 东京生活服务")
                MerchantPickerField(icon: "tag", title: "商家类型", required: true, selection: $businessType, values: businessTypes)
                MerchantField(icon: "doc.text", title: "主体全称", required: true, text: $legalName, placeholder: "株式会社 / 个体事业者 / 法人主体")
                MerchantField(icon: "person.text.rectangle", title: "负责人姓名", required: true, text: $representativeName, placeholder: "负责人或联系人", capitalization: .words)
                MerchantField(icon: "number", title: "登记号 / 许可编号", text: $registrationNumber, placeholder: "法人番号、营业执照编号、许可编号")

                MerchantFormGroupHeader(icon: "mappin.and.ellipse", title: "联系与位置", tint: .blue)
                MerchantTapField(icon: "globe.asia.australia", title: "经营城市", required: true, valueLabel: regionFieldLabel) {
                    isRegionPickerPresented = true
                }
                MerchantField(icon: "phone", title: "电话 / Line / WhatsApp", required: true, text: $phone, placeholder: "+81 90...", keyboard: .phonePad)
                MerchantField(icon: "envelope", title: "联系邮箱", text: $email, placeholder: "business@example.com", keyboard: .emailAddress)
                MerchantField(icon: "link", title: "官网 / 社媒", text: $website, placeholder: "https://...", keyboard: .URL)
                MerchantField(icon: "location", title: "经营地址", required: true, text: $address, placeholder: "东京都新宿区...")
                MerchantField(icon: "signpost.right", title: "邮编", text: $postalCode, placeholder: "160-0022", keyboard: .numbersAndPunctuation)
                MerchantField(icon: "bubble.left.and.text.bubble.right", title: "公开联系方式", text: $contactMethod, placeholder: "站内信 / 电话 / Line / 官网表单")

                MerchantFormGroupHeader(icon: "sparkles", title: "服务内容", tint: .orange)
                VStack(alignment: .leading, spacing: 8) {
                    MerchantFieldTitle(title: "服务分类", required: true)
                    FlowTags(values: serviceCategories, selected: $selectedCategories)
                }
                MerchantTextEditor(icon: "text.alignleft", title: "服务介绍", required: true, text: $serviceDescription, placeholder: "介绍服务范围、价格区间、服务语言、预约方式、退款/取消规则等。")
                MerchantTextEditor(icon: "paperclip", title: "申请备注", text: $applicationNote, placeholder: "补充资质、门店照片、平台链接、过往案例等。")

                VStack(spacing: 10) {
                    Button {
                        Task { await save(submit: true) }
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                KXSpinner(size: 16, lineWidth: 2.2)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(isSaving ? "提交中" : "提交认证审核")
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
                        Label(isSaving ? "保存中" : "仅保存资料", systemImage: "tray.and.arrow.down")
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
                .padding(.top, 2)
            }
            .padding(14)
        }
    }

    private var documentSection: some View {
        SettingsSectionCard(title: "认证材料") {
            VStack(alignment: .leading, spacing: 12) {
                Text("支持 PDF 或图片：营业执照、法人登记、许可证明、负责人身份证明等。材料为私密文件，仅本人和后台可查看。正式提交审核至少需要 1 份材料。")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                Button {
                    isImporterPresented = true
                } label: {
                    HStack(spacing: 8) {
                        if isUploading {
                            KXSpinner(size: 16, lineWidth: 2.2)
                        } else {
                            Image(systemName: "doc.badge.plus")
                        }
                        Text(isUploading ? "上传中" : "上传材料")
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
                    Text("还没有上传认证材料。")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(docs) { doc in
                            HStack(spacing: 10) {
                                Image(systemName: doc.contentType == "application/pdf" ? "doc.richtext.fill" : "photo.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(doc.documentType ?? "认证材料")
                                        .font(.subheadline.weight(.bold))
                                    Text("\(formatBytes(doc.fileSize ?? 0)) · \(doc.status ?? doc.documentStatus ?? "submitted")")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("私密")
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 8)
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
                                    .accessibilityLabel("撤回认证材料")
                                }
                            }
                            .padding(10)
                            .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var reviewNoteSection: some View {
        if let note = business?.review_note, !note.isEmpty {
            SettingsSectionCard(title: "后台审核意见") {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(12)
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
        case "pending": return "审核中"
        case "needs_review": return "需补充材料"
        case "rejected": return "未通过"
        case "suspended": return "已暂停"
        case "draft": return "草稿"
        default: return "未申请"
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
        businessType = profile.business_type.isEmpty ? "生活服务" : profile.business_type
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
        selectedCategories = Set(profile.service_categories?.isEmpty == false ? profile.service_categories ?? [] : ["生活服务"])
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
                message = submit ? "已提交认证审核，后台会人工审核。" : "商家资料已保存。"
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
        if businessName.trimmed.isEmpty { return "请填写商家/品牌名称。" }
        guard submit else { return nil }
        var missing: [String] = []
        if businessType.trimmed.isEmpty { missing.append("商家类型") }
        if legalName.trimmed.isEmpty { missing.append("主体全称") }
        if representativeName.trimmed.isEmpty { missing.append("负责人姓名") }
        if countryCode.trimmed.isEmpty { missing.append("国家") }
        if citySlug.trimmed.isEmpty { missing.append("城市") }
        if phone.trimmed.isEmpty && email.trimmed.isEmpty { missing.append("电话或邮箱") }
        if address.trimmed.isEmpty { missing.append("经营地址") }
        if serviceDescription.trimmed.isEmpty { missing.append("服务介绍") }
        if selectedCategories.isEmpty { missing.append("服务分类") }
        let documentCount = business?.documents?.count ?? 0
        if documentCount + pendingUploadedFileIds.count <= 0 { missing.append("认证材料") }
        return missing.isEmpty ? nil : "请完善：" + missing.joined(separator: "、")
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
                message = "请先填写商家名称并保存资料。"
                return
            }
            isUploading = true
            defer { isUploading = false }
            var uploadedIds: [String] = []
            for url in urls.prefix(10) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
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
            message = "已上传 \(uploadedIds.count) 份认证材料。"
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
            message = "认证材料已撤回。"
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
        if bytes <= 0 { return "文件" }
        if bytes < 1_048_576 { return "\(max(1, bytes / 1024)) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }
}

private struct MerchantMetricTile: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(12)
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
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.bold))
            Rectangle()
                .fill(KXColor.separator.opacity(0.7))
                .frame(height: 0.7)
        }
        .padding(.top, 4)
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
                }
            }
            .padding(.horizontal, 12)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MerchantFieldTitle(title: title, required: required)
            Menu {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        if selection == value {
                            Label(value, systemImage: "checkmark")
                        } else {
                            Text(value)
                        }
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(selection)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                MerchantFieldTitle(title: title, required: required)
                Spacer()
                if !text.isEmpty {
                    Text("\(text.count) 字")
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
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
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

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
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
                    HStack(spacing: 4) {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.black))
                        }
                        Text(value)
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
