import Foundation
import Combine
import CoreLocation

/// One-shot Core Location helper that turns the device's current position into
/// a `KaiXRegionDirectory.Region` (current city). Used so users don't have to
/// pick their city by hand — the home / discover region chip and the composer
/// can auto-fill from where they actually are.
///
/// City-level accuracy is plenty (`kCLLocationAccuracyKilometer`), so we never
/// ask for precise/always permission — just When-In-Use, one fix, reverse
/// geocoded with an English locale so the placemark fields line up with the
/// directory's romaji/pinyin province codes.
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    enum Phase: Equatable {
        case idle          // never run
        case requesting    // waiting on the permission prompt
        case locating      // permission granted, getting a fix + geocoding
        case success
        case denied        // user said no / restricted
        case failed        // timed out or couldn't resolve a city
    }

    @Published private(set) var phase: Phase = .idle

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    /// 在途的一次定位。共享单例 + 单 continuation 槽,重叠调用(启动自动定位 vs
    /// RegionPicker「使用当前位置」)必须合流到同一次定位,否则第二次会覆盖第一
    /// 次的 continuation(永不 resume → CONTINUATION MISUSE 泄漏)。
    private var inFlightFix: Task<CLLocation?, Never>?
    /// 12s 看门狗句柄:成功 resume 时必须 cancel,否则前一次残留的看门狗会把
    /// 下一次还在等待的定位用 nil 提前打断。
    private var watchdog: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }
    var isDenied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    /// Request permission if needed, grab a single fix, reverse-geocode it to a
    /// directory Region. Returns nil (and sets `phase`) on denial / failure.
    @discardableResult
    func detectRegion() async -> KaiXRegionDirectory.Region? {
        if isDenied { phase = .denied; return nil }
        phase = manager.authorizationStatus == .notDetermined ? .requesting : .locating

        guard let location = await requestLocation() else {
            phase = isDenied ? .denied : .failed
            return nil
        }

        phase = .locating
        let region = await reverseGeocode(location)
        phase = region == nil ? .failed : .success
        return region
    }

    // MARK: - One fix

    private func requestLocation() async -> CLLocation? {
        // 重叠调用合流:第二个调用者直接等同一次定位结果,绝不覆盖单例上
        // 唯一的 continuation 槽。
        if let inFlight = inFlightFix {
            return await inFlight.value
        }
        let task = Task { @MainActor in
            await self.performLocationFix()
        }
        inFlightFix = task
        let result = await task.value
        inFlightFix = nil
        return result
    }

    private func performLocationFix() async -> CLLocation? {
        await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = cont
            // Watchdog: never leave the await hanging if no callback arrives.
            // 先建看门狗再走 switch(default 分支会同步 finish 并顺手 cancel 它);
            // 句柄保存在 self.watchdog,finish() 时取消,防止陈旧看门狗打断
            // 下一次定位。
            watchdog = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }
                self.finish(nil)
            }
            switch manager.authorizationStatus {
            case .notDetermined:
                // The auth-change delegate kicks off requestLocation() once granted.
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        watchdog?.cancel()
        watchdog = nil
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: location)
    }

    private func reverseGeocode(_ location: CLLocation) async -> KaiXRegionDirectory.Region? {
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.reverseGeocodeLocation(
            location,
            preferredLocale: Locale(identifier: "en_US")
        )
        guard let placemark = placemarks?.first else { return nil }
        return KaiXRegionDirectory.match(
            isoCountryCode: placemark.isoCountryCode,
            adminArea: placemark.administrativeArea,
            locality: placemark.locality ?? placemark.subAdministrativeArea
        )
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.phase = .denied
                self.finish(nil)
            case .notDetermined:
                break
            @unknown default:
                self.finish(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.finish(locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
