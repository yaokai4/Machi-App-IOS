import Foundation
import Combine

/// Holds the user's currently-browsing region and a short list of
/// recently-visited regions. Persisted to UserDefaults so it survives
/// app relaunches. Backed by the in-process `KaiXRegionDirectory`
/// (no network), which is enough for everything in Phase 1.
///
/// **Relationship to UserEntity:** `UserEntity.country/province/city`
/// is the user's *declared home* (what they're showing on their
/// profile and the server-side default for "local feed"). The store
/// below tracks what they're currently *browsing*, which is allowed to
/// differ — e.g. someone based in Shanghai who's visiting Tokyo for a
/// week should see Tokyo content without having to update their
/// declared home.
@MainActor
final class RegionStore: ObservableObject {
    static let shared = RegionStore()

    @Published private(set) var current: KaiXRegionDirectory.Region?
    @Published private(set) var recent: [KaiXRegionDirectory.Region] = []

    private let currentKey = "kaix.region.current"
    private let recentKey  = "kaix.region.recent"
    private let recentCap  = 8

    private init() {
        if let code = UserDefaults.standard.string(forKey: currentKey) {
            if let region = KaiXRegionDirectory.resolve(regionCode: code) {
                self.current = region
            } else {
                UserDefaults.standard.removeObject(forKey: currentKey)
            }
        }
        if let codes = UserDefaults.standard.stringArray(forKey: recentKey) {
            var seen = Set<String>()
            let cleaned = codes
                .compactMap { KaiXRegionDirectory.resolve(regionCode: $0) }
                .filter { seen.insert($0.regionCode).inserted }
            self.recent = cleaned
            let cleanedCodes = cleaned.map(\.regionCode)
            if cleanedCodes != codes {
                UserDefaults.standard.set(cleanedCodes, forKey: recentKey)
            }
        }
    }

    /// Set the currently-browsing region, push it onto the recent
    /// list, and persist both. UI bound to `current` / `recent`
    /// updates immediately.
    func setCurrent(_ region: KaiXRegionDirectory.Region) {
        current = region
        UserDefaults.standard.set(region.regionCode, forKey: currentKey)
        // Dedupe + cap. New selection moves to the front so the
        // picker's "recently used" row stays useful.
        var next = [region] + recent.filter { $0.regionCode != region.regionCode }
        if next.count > recentCap { next = Array(next.prefix(recentCap)) }
        recent = next
        UserDefaults.standard.set(next.map(\.regionCode), forKey: recentKey)
    }

    /// Restore the app-side browsing region from the signed-in user's
    /// saved home region. Called after login / account switch so a
    /// newly authenticated account immediately stays in its chosen
    /// country and city.
    func applyUserRegion(_ user: UserEntity) {
        let region = KaiXRegionDirectory.resolve(regionCode: user.currentRegionCode)
            ?? KaiXRegionDirectory.make(
                country: user.country,
                province: user.province.isEmpty ? nil : user.province,
                city: user.city
            )
        guard let region else { return }

        current = region
        UserDefaults.standard.set(region.regionCode, forKey: currentKey)

        var seen = Set<String>()
        var next = ([region] + user.recentRegionCodes.compactMap {
            KaiXRegionDirectory.resolve(regionCode: $0)
        })
        .filter { seen.insert($0.regionCode).inserted }
        if next.count > recentCap { next = Array(next.prefix(recentCap)) }
        recent = next
        UserDefaults.standard.set(next.map(\.regionCode), forKey: recentKey)
    }

    /// Convenience: set the current region from raw slugs (e.g. from
    /// onboarding's free-form picker before we have a Region object).
    @discardableResult
    func setCurrent(country: String, province: String?, city: String) -> KaiXRegionDirectory.Region? {
        guard let region = KaiXRegionDirectory.make(country: country, province: province, city: city) else {
            return nil
        }
        setCurrent(region)
        return region
    }

    /// Clear everything (called from logout so the next account
    /// starts with a fresh picker).
    func reset() {
        current = nil
        recent = []
        UserDefaults.standard.removeObject(forKey: currentKey)
        UserDefaults.standard.removeObject(forKey: recentKey)
    }
}
