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

    private let identityOptions: [(value: String, label: (String, String, String))] = [
        ("student", ("大学生", "大学生", "University")),
        ("language_school_student", ("语言学校", "語学学校", "Language school")),
        ("worker", ("社会人", "社会人", "Working")),
        ("career_change", ("转职", "転職", "Career change")),
        ("applicant", ("升学", "進学", "Applicant")),
    ]

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(title: guideOSText(language, "个人提醒设置", "個人リマインダー設定", "Personal reminders"), subtitle: guideOSText(language, "不需要上传在留卡或护照，全部可选。填一个你希望被提醒的日期，Machi 就会生成 Todo、倒数日和日历提醒。", "在留カードやパスポートのアップロードは不要、すべて任意です。通知してほしい日付を一つ入れると、Todo・カウントダウン・カレンダーを作成します。", "No residence card or passport upload — everything is optional. Add one date you want to be reminded of and Machi creates a todo, countdown, and calendar alert."))

                    // Concrete reminder cards. Each states its payoff up front, so
                    // users know exactly what filling it in does — no abstract
                    // identity wizard to puzzle over.
                    GuideReminderDateCard(
                        icon: "person.text.rectangle.fill",
                        tint: .cyan,
                        title: guideOSText(language, "在留卡 / 签证到期", "在留カード / ビザ期限", "Residence card / visa expiry"),
                        payoff: guideOSText(language, "填了之后：在到期前自动生成续签倒排 Todo 和日历提醒", "入力すると：期限前に更新の逆算Todoとカレンダー通知を自動生成", "Once added: a renewal countdown todo and calendar alert before it expires"),
                        toggleTitle: guideOSText(language, "记录到期日", "期限を記録", "Track expiry"),
                        isOn: $hasVisaExpiry,
                        date: $visaExpiry
                    )
                    GuideReminderDateCard(
                        icon: "graduationcap.fill",
                        tint: KXColor.accent,
                        title: guideOSText(language, "毕业 / 入社日", "卒業 / 入社日", "Graduation / start date"),
                        payoff: guideOSText(language, "填了之后：自动生成升学或就活的时间线提醒", "入力すると：進学・就活のタイムライン通知を自動生成", "Once added: a study or job-hunting timeline reminder"),
                        toggleTitle: guideOSText(language, "记录日期", "日付を記録", "Track date"),
                        isOn: $hasGraduationDate,
                        date: $graduationDate
                    )

                    GuidePermanentResidencyHint(visaExpiry: hasVisaExpiry ? visaExpiry : nil)

                    // Identity is now a single optional control whose only job — and
                    // we say so — is ordering the most relevant guides first.
                    VStack(alignment: .leading, spacing: 10) {
                        Text(guideOSText(language, "你的身份（可选）", "あなたの状況（任意）", "Your status (optional)"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Picker(guideOSText(language, "身份", "状況", "Status"), selection: $identityType) {
                            ForEach(identityOptions, id: \.value) { option in
                                Text(guideOSText(language, option.label.0, option.label.1, option.label.2)).tag(option.value)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(guideOSText(language, "仅用于把最相关的指南排在前面，可以不选。", "最も関連するガイドを上位に並べるためだけに使います。未選択でもOK。", "Only used to surface the most relevant guides first. Optional."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(15)
                    .kxGlassSurface(radius: 22)

                    // City stays available but de-emphasised under "更多（可选）".
                    VStack(alignment: .leading, spacing: 10) {
                        Text(guideOSText(language, "城市（可选）", "都市（任意）", "City (optional)"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        GuideOSTextField(title: guideOSText(language, "城市", "都市", "City"), text: $city)
                        Button {
                            locator.request()
                        } label: {
                            Label(locator.isLocating ? guideOSText(language, "获取当前位置中", "現在地を取得中", "Locating") : guideOSText(language, "使用当前位置", "現在地を使う", "Use current location"), systemImage: "location.fill")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                        }
                        .buttonStyle(.fullArea)
                        .contentShape(Rectangle())
                        .foregroundStyle(KXColor.accent)
                        .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        Toggle(guideOSText(language, "目前在日本", "現在日本にいる", "Currently in Japan"), isOn: $isInJapan)
                    }
                    .padding(15)
                    .kxGlassSurface(radius: 22)

                    Button {
                        Task {
                            await model.saveProfile(.init(
                                identityType: identityType,
                                city: city,
                                isInJapan: isInJapan,
                                // 服务端 api_guide_profile_update 是整行重写:漏传
                                // arrivalStage 会把 onboarding persona 清空。这个
                                // 表单不编辑来日阶段,回传已加载 profile 的现值。
                                arrivalStage: model.profile?.arrivalStage,
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
                        Text(model.isSaving ? guideOSText(language, "保存中", "保存中", "Saving") : guideOSText(language, "保存提醒设置", "リマインダーを保存", "Save reminders"))
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .foregroundStyle(.white)
                    .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

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

/// A single optional reminder: a titled card that explains its payoff, a toggle
/// to opt in, and (when on) a date picker. Replaces the old 3-step identity
/// wizard — users see exactly what each field does before filling it.
private struct GuideReminderDateCard: View {
    let icon: String
    let tint: Color
    let title: String
    let payoff: String
    let toggleTitle: String
    @Binding var isOn: Bool
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(payoff)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Toggle(toggleTitle, isOn: $isOn.animation(.easeInOut(duration: 0.2)))
                .font(.subheadline.weight(.semibold))
            if isOn {
                DatePicker(title, selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(15)
        .kxGlassSurface(radius: 22)
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
