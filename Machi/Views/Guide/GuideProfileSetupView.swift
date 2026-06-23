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

    private var schoolPath: Bool { ["student", "language_school_student", "applicant"].contains(identityType) }
    private var careerPath: Bool { ["worker", "career_change"].contains(identityType) }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(title: guideOSText(language, "身份路径", "属性ルート", "Profile route"), subtitle: guideOSText(language, "填好身份和在留/毕业时间，Machi 会自动生成在留更新倒计时、就活/升学时间线和你的专属计划。", "属性と在留/卒業時期を入力すると、在留更新のカウントダウン・就活/進学のタイムライン・専用プランを自動生成します。", "Set your identity and visa/graduation dates and Machi auto-generates a renewal countdown, a job/study timeline, and your personalized plan."))
                    VStack(spacing: 12) {
                        Picker(guideOSText(language, "身份", "属性", "Identity"), selection: $identityType) {
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
                        Toggle("需要资料包", isOn: $needsMaterials)
                        Toggle("需要咨询/代办服务", isOn: $needsServices)
                        GuidePermanentResidencyHint(visaExpiry: hasVisaExpiry ? visaExpiry : nil)
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
                            Text(model.isSaving ? "保存中" : "保存身份路径")
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
        .navigationTitle(guideOSText(language, "身份", "属性", "Profile"))
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
