import CoreLocation
import Combine
import SwiftUI

struct GuideProfileSetupView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideProfileViewModel()
    @StateObject private var locator = GuideProfileLocationProvider()
    @State private var identityType = "student"
    @State private var city = "tokyo"
    @State private var isInJapan = true
    @State private var visaStatus = ""
    @State private var hasVisaExpiry = false
    @State private var visaExpiry = Date()
    @State private var japaneseLevel = "N3"
    @State private var targetJapaneseLevel = "N2"
    @State private var hasGraduationDate = false
    @State private var graduationDate = Date()
    @State private var targetEntryTerm = ""
    @State private var targetIndustry = ""
    @State private var targetSchoolType = ""
    @State private var weeklyMinutes = 360
    @State private var needsMaterials = true
    @State private var needsServices = false
    @State private var step = 0

    private var schoolPath: Bool { ["student", "language_school_student", "applicant"].contains(identityType) }
    private var careerPath: Bool { ["worker", "career_change"].contains(identityType) }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(title: guideOSText(language, "个人提醒设置", "個人リマインダー設定", "Personal reminders"), subtitle: guideOSText(language, "不需要上传在留卡或护照。只填写你希望被提醒的日期，Machi 会生成 Todo、倒数日和日历提醒。", "在留カードやパスポートのアップロードは不要です。通知してほしい日付だけ入力すると、Todo・カウントダウン・カレンダーを作成します。", "No residence card or passport upload is needed. Add reminder dates and Machi creates todos, countdowns, and calendar alerts."))
                    VStack(spacing: 12) {
                        GuideProfileStepTabs(step: $step)
                        if step == 0 {
                            Picker(guideOSText(language, "当前状态", "現在の状況", "Current status"), selection: $identityType) {
                                Text(guideOSText(language, "大学生", "大学生", "University")).tag("student")
                                Text(guideOSText(language, "语言学校", "語学学校", "Language school")).tag("language_school_student")
                                Text(guideOSText(language, "社会人", "社会人", "Working")).tag("worker")
                                Text(guideOSText(language, "转职", "転職", "Career change")).tag("career_change")
                                Text(guideOSText(language, "升学", "進学", "Applicant")).tag("applicant")
                            }
                            .pickerStyle(.segmented)
                            GuideOSTextField(title: "城市", text: $city)
                            Button {
                                locator.request()
                            } label: {
                                Label(locator.isLocating ? "获取当前位置中" : "使用当前位置", systemImage: "location.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .foregroundStyle(KXColor.accent)
                            .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            Toggle("目前在日本", isOn: $isInJapan)
                            GuideOSTextField(title: "签证 / 在留状态", text: $visaStatus)
                            Toggle("记录在留期限", isOn: $hasVisaExpiry)
                            if hasVisaExpiry {
                                DatePicker("在留期限", selection: $visaExpiry, displayedComponents: .date)
                            }
                            GuidePermanentResidencyHint(visaExpiry: hasVisaExpiry ? visaExpiry : nil)
                        } else if step == 1 {
                            HStack {
                                GuideOSTextField(title: "当前日语", text: $japaneseLevel)
                                GuideOSTextField(title: "目标日语", text: $targetJapaneseLevel)
                            }
                            if schoolPath {
                                Toggle("记录毕业 / 修了预计", isOn: $hasGraduationDate)
                                if hasGraduationDate {
                                    DatePicker("毕业 / 修了预计", selection: $graduationDate, displayedComponents: .date)
                                }
                                GuideOSTextField(title: "目标入学期", text: $targetEntryTerm)
                                GuideOSTextField(title: "目标学校类型", text: $targetSchoolType)
                                GuideOSTextField(title: "研究方向 / 专攻", text: $targetIndustry)
                            } else if careerPath {
                                GuideOSTextField(title: "目标入社期", text: $targetEntryTerm)
                                GuideOSTextField(title: "目标行业 / 职种", text: $targetIndustry)
                            } else {
                                GuideOSTextField(title: "目标入学期 / 入社期", text: $targetEntryTerm)
                                GuideOSTextField(title: "目标行业", text: $targetIndustry)
                            }
                            Stepper("每周可投入 \(weeklyMinutes) 分钟", value: $weeklyMinutes, in: 60...2400, step: 60)
                        } else {
                            Toggle("需要资料包", isOn: $needsMaterials)
                            Toggle("需要咨询/代办服务", isOn: $needsServices)
                            GuideProfileGeneratedPreview(
                                hasVisaExpiry: hasVisaExpiry,
                                visaExpiry: visaExpiry,
                                hasGraduationDate: hasGraduationDate,
                                graduationDate: graduationDate,
                                needsMaterials: needsMaterials,
                                needsServices: needsServices
                            )
                        }
                        HStack(spacing: 10) {
                            if step > 0 {
                                Button {
                                    step -= 1
                                } label: {
                                    Text("上一步")
                                        .font(.subheadline.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(KXColor.accent)
                                .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            if step < 2 {
                                Button {
                                    step += 1
                                } label: {
                                    Text("下一步")
                                        .font(.subheadline.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)
                                .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        Button {
                            Task {
                                await model.saveProfile(.init(
                                    identityType: identityType,
                                    city: city,
                                    isInJapan: isInJapan,
                                    visaStatus: visaStatus,
                                    visaExpiresAt: hasVisaExpiry ? GuideOSDate.iso(visaExpiry) : nil,
                                    japaneseLevel: japaneseLevel,
                                    targetJapaneseLevel: targetJapaneseLevel,
                                    graduationDate: hasGraduationDate ? GuideOSDate.iso(graduationDate) : nil,
                                    targetEntryTerm: targetEntryTerm,
                                    targetIndustry: targetIndustry,
                                    targetSchoolType: targetSchoolType,
                                    weeklyAvailableMinutes: weeklyMinutes,
                                    needsMaterials: needsMaterials,
                                    needsServices: needsServices
                                ))
                            }
                        } label: {
                            Text(model.isSaving ? "保存中" : "保存提醒设置")
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .foregroundStyle(.white)
                        .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .padding(15)
                    .kxGlassSurface(radius: 22)
                    if let message = model.message { GuideOSNotice(message: message) }
                    if let message = locator.message { GuideOSNotice(message: message) }
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "提醒设置", "リマインダー", "Reminders"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !model.requireLogin() { return }
            await model.loadProfile()
            if let profile = model.profile {
                identityType = profile.identityType.isEmpty ? identityType : profile.identityType
                city = profile.city.isEmpty ? city : profile.city
                isInJapan = profile.isInJapan
                visaStatus = profile.visaStatus
                if let raw = profile.visaExpiresAt, let date = GuideProfileDate.parse(raw) {
                    hasVisaExpiry = true
                    visaExpiry = date
                }
                japaneseLevel = profile.japaneseLevel.isEmpty ? japaneseLevel : profile.japaneseLevel
                targetJapaneseLevel = profile.targetJapaneseLevel.isEmpty ? targetJapaneseLevel : profile.targetJapaneseLevel
                if let raw = profile.graduationDate, let date = GuideProfileDate.parse(raw) {
                    hasGraduationDate = true
                    graduationDate = date
                }
                targetEntryTerm = profile.targetEntryTerm
                targetIndustry = profile.targetIndustry
                targetSchoolType = profile.targetSchoolType
                weeklyMinutes = max(60, profile.weeklyAvailableMinutes)
                needsMaterials = profile.needsMaterials
                needsServices = profile.needsServices
            }
        }
        .onChange(of: locator.city) { _, value in
            if !value.isEmpty {
                city = value
                isInJapan = true
            }
        }
    }
}

private struct GuideProfileStepTabs: View {
    @Environment(\.appLanguage) private var language
    @Binding var step: Int
    private var labels: [String] {
        [
            guideOSText(language, "状态", "状況", "Status"),
            guideOSText(language, "目标", "目標", "Goal"),
            guideOSText(language, "生成", "生成", "Output")
        ]
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Button {
                    step = index
                } label: {
                    Text("\(index + 1). \(label)")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .foregroundStyle(step == index ? KXColor.accent : .secondary)
                .background(step == index ? Color.white.opacity(0.9) : Color.clear, in: Capsule())
            }
        }
        .padding(4)
        .background(KXColor.softBackground, in: Capsule())
    }
}

private struct GuideProfileGeneratedPreview: View {
    @Environment(\.appLanguage) private var language
    let hasVisaExpiry: Bool
    let visaExpiry: Date
    let hasGraduationDate: Bool
    let graduationDate: Date
    let needsMaterials: Bool
    let needsServices: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(guideOSText(language, "保存后会同步", "保存後に同期", "Generated after saving"))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            previewRow(
                active: hasVisaExpiry,
                title: guideOSText(language, "在留更新倒排", "在留更新の逆算", "Visa renewal countdown"),
                body: hasVisaExpiry ? GuideOSDate.iso(visaExpiry) : guideOSText(language, "填写在留期限后生成 Todo 与提醒", "在留期限を入れるとTodoと通知を作成", "Add expiry to create todo and reminder")
            )
            previewRow(
                active: hasGraduationDate,
                title: guideOSText(language, "毕业 / 入社时间线", "卒業 / 入社タイムライン", "Graduation / start timeline"),
                body: hasGraduationDate ? GuideOSDate.iso(graduationDate) : guideOSText(language, "填写日期后生成升学或就活倒排", "日付を入れると進学/就活の逆算を作成", "Add date to create study/job timeline")
            )
            previewRow(
                active: needsMaterials || needsServices,
                title: guideOSText(language, "资料 / 服务推荐", "資料 / サービス推薦", "Resources / services"),
                body: guideOSText(language, "会跟随 Todo 出现在任务上下文里", "Todoの文脈に合わせて表示", "Shown in the context of each todo")
            )
        }
        .padding(12)
        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func previewRow(active: Bool, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.bold))
                .foregroundStyle(active ? KXColor.accent : .secondary)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text(body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private enum GuideProfileDate {
    static func parse(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(raw.prefix(10)))
    }
}

private struct GuidePermanentResidencyHint: View {
    let visaExpiry: Date?
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(guideOSText(language, "长期在日与永住准备", "長期在留・永住の準備", "Long-term stay & PR prep"), systemImage: "checkmark.shield.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(KXColor.accent)
            Text(guideOSText(language,
                "先把城市、在留资格、在留期限、毕业/入社时间、日语目标保存好。未来判断永住、高度人才或签证更新时，通常会回看居住年数、纳税年金、收入稳定性、在留期限和材料连续性；具体条件以入管最新公告为准。",
                "都市・在留資格・在留期限・卒業/入社時期・日本語目標を保存しておきましょう。永住・高度人材・ビザ更新の判断では、居住年数・納税年金・収入の安定・在留期限・書類の連続性が見られます。詳細は入管の最新公告をご確認ください。",
                "Save your city, status of residence, expiry, graduation/start date, and Japanese goal. PR, HSP, and visa renewals typically look at years of residence, taxes/pension, income stability, expiry, and document continuity — always check Immigration's latest notice."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let visaExpiry {
                Text(guideOSText(language, "在留期限倒数", "在留期限まで", "Status expires in") + " \(max(0, Calendar.current.dateComponents([.day], from: Date(), to: visaExpiry).day ?? 0)) " + guideOSText(language, "天", "日", "days"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private final class GuideProfileLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var city = ""
    @Published var message: String?
    @Published var isLocating = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        message = nil
        isLocating = true
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            isLocating = false
            message = "定位权限未开启，可以手动填写城市。"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isLocating = false
            return
        }
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let place = placemarks?.first
                self.city = place?.locality ?? place?.administrativeArea ?? "\(location.coordinate.latitude), \(location.coordinate.longitude)"
                self.isLocating = false
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        message = "定位失败，可以手动填写城市。"
    }
}
