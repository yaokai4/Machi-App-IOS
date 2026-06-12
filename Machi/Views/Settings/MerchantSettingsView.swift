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
    @State private var message: String?
    @State private var pendingUploadedFileIds: [String] = []

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

    private let businessTypes = ["餐厅美食", "咖啡甜品", "生活服务", "民宿 / 酒店", "景点票务", "教育培训", "房产服务", "招聘雇主", "搬家清洁", "翻译手续", "维修安装"]
    private let serviceCategories = ["餐厅美食", "在线订座", "优惠团购", "民宿", "酒店", "温泉旅馆", "公寓式酒店", "景点门票", "一日游", "接送机", "翻译手续", "搬家清洁", "维修安装", "本地向导", "认证服务"]

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
            .padding(.bottom, 42)
        }
        .navigationTitle("商家服务后台")
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .task { await load() }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            Task { await handleFileImport(result) }
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
                    .foregroundStyle(statusTint)
                    .frame(width: 46, height: 46)
                    .background(statusTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(business?.business_name.isEmpty == false ? business?.business_name ?? "申请认证商家服务" : "申请认证商家服务")
                        .font(.title3.weight(.bold))
                    Text(statusLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusTint)
                }
                Spacer()
            }
            Text("商家与本地服务覆盖餐厅美食、在线订座、优惠、民宿酒店、景点票务、一日游、接送机和生活支持。提交后会进入总后台人工审核，Web 与 iOS 同步显示认证状态。")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            if let message {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(message.hasPrefix("已") || message.contains("成功") ? .green : .secondary)
            }
        }
        .padding(16)
        .kxGlassSurface(radius: 24, elevated: true)
    }

    private var dashboardCard: some View {
        SettingsSectionCard(title: "经营看板") {
            if isLoading {
                ProgressView("正在加载商家资料")
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

    private var applicationForm: some View {
        SettingsSectionCard(title: "认证资料") {
            VStack(spacing: 12) {
                MerchantTextField(title: "商家/品牌名称 *", text: $businessName, placeholder: "Machi Coffee / 东京生活服务")
                MerchantPickerField(title: "商家类型 *", selection: $businessType, values: businessTypes)
                MerchantTextField(title: "主体全称 *", text: $legalName, placeholder: "株式会社 / 个体事业者 / 法人主体")
                MerchantTextField(title: "负责人姓名 *", text: $representativeName, placeholder: "负责人或联系人")
                MerchantTextField(title: "登记号 / 许可编号", text: $registrationNumber, placeholder: "法人番号、营业执照编号、许可编号")
                HStack(spacing: 10) {
                    MerchantTextField(title: "国家", text: $countryCode, placeholder: "jp")
                    MerchantTextField(title: "城市 *", text: $citySlug, placeholder: "tokyo")
                }
                MerchantTextField(title: "电话 / Line / WhatsApp *", text: $phone, placeholder: "+81 90...")
                MerchantTextField(title: "联系邮箱", text: $email, placeholder: "business@example.com")
                MerchantTextField(title: "官网 / 社媒", text: $website, placeholder: "https://...")
                MerchantTextField(title: "经营地址 *", text: $address, placeholder: "东京都新宿区...")
                MerchantTextField(title: "邮编", text: $postalCode, placeholder: "160-0022")
                MerchantTextField(title: "公开联系方式", text: $contactMethod, placeholder: "站内信 / 电话 / Line / 官网表单")

                VStack(alignment: .leading, spacing: 8) {
                    Text("服务分类 *")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    FlowTags(values: serviceCategories, selected: $selectedCategories)
                }

                MerchantTextEditor(title: "服务介绍 *", text: $serviceDescription, placeholder: "介绍服务范围、价格区间、服务语言、预约方式、退款/取消规则等。")
                MerchantTextEditor(title: "申请备注", text: $applicationNote, placeholder: "补充资质、门店照片、平台链接、过往案例等。")

                HStack(spacing: 10) {
                    Button {
                        Task { await save(submit: false) }
                    } label: {
                        Label(isSaving ? "保存中" : "保存资料", systemImage: "tray.and.arrow.down.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving || isUploading)

                    Button {
                        Task { await save(submit: true) }
                    } label: {
                        Label(isSaving ? "提交中" : "提交认证审核", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || isUploading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
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
                    Label(isUploading ? "上传中" : "上传材料", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.title3.weight(.black))
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MerchantTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct MerchantPickerField: View {
    let title: String
    @Binding var selection: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MerchantTextEditor: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.secondary.opacity(0.65))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $text)
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
            }
            .padding(6)
            .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct FlowTags: View {
    let values: [String]
    @Binding var selected: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            ForEach(values, id: \.self) { value in
                Button {
                    if selected.contains(value) {
                        selected.remove(value)
                    } else {
                        selected.insert(value)
                    }
                } label: {
                    Text(value)
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .foregroundStyle(selected.contains(value) ? KXColor.accent : .secondary)
                        .background(selected.contains(value) ? KXColor.accent.opacity(0.12) : KXColor.softBackground, in: Capsule())
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
