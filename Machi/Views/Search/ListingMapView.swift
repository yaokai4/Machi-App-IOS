import CoreLocation
import MapKit
import SwiftUI

/// Best-effort, client-side geocoding cache (Apple `CLGeocoder` — free, no API
/// key, no backend). Listings carry only free-text locations, so we geocode the
/// cleanest available signal on device. CLGeocoder permits one request at a
/// time, so callers must `await` serially. Results (and misses) are cached for
/// the app session.
@MainActor
final class ListingGeocodeCache {
    static let shared = ListingGeocodeCache()

    private var hits: [String: CLLocationCoordinate2D] = [:]
    private var misses: Set<String> = []
    private let geocoder = CLGeocoder()
    /// 串行化闸门:CLGeocoder 一次只接受一个请求。切筛选会让新旧两个
    /// resolve 循环短暂并发,若不排队,并发调用必抛限流错——曾经的实现把
    /// 任何 catch 都写进 misses,一批真实车站就此被永久打成「不可映射」。
    private var chain: Task<Void, Never>?

    func resolve(_ key: String) async -> CLLocationCoordinate2D? {
        if let c = hits[key] { return c }
        if misses.contains(key) { return nil }
        let previous = chain
        let task = Task<Void, Never> { [weak self] in
            _ = await previous?.value
            await self?.performGeocode(key)
        }
        chain = task
        _ = await task.value
        return hits[key]
    }

    private func performGeocode(_ key: String) async {
        // 排队期间可能已被前一个同 key 请求解决。
        if hits[key] != nil || misses.contains(key) { return }
        do {
            let placemarks = try await geocoder.geocodeAddressString(key)
            if let coord = placemarks.first?.location?.coordinate {
                hits[key] = coord
            } else {
                misses.insert(key)
            }
        } catch {
            // 只有「真·无结果」才永久缓存为 miss;网络抖动 / 限流(kCLErrorNetwork
            // 等)不缓存,下次进入地图还能重试——否则一次限流会话内不可恢复。
            if let code = (error as? CLError)?.code, code == .geocodeFoundNoResult {
                misses.insert(key)
            }
        }
    }
}

struct ListingMapPin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let listing: KaiXCityListingDTO
}

/// Airbnb-style map of the current results. Pins are price badges; tapping one
/// raises a compact card that opens the detail. Coverage depends on how cleanly
/// each listing's location geocodes — unmappable ones are simply omitted.
struct ListingMapView: View {
    @Environment(\.appLanguage) private var language
    let listings: [KaiXCityListingDTO]
    let onOpen: (String) -> Void

    @State private var pins: [ListingMapPin] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: ListingMapPin?
    @State private var isResolving = true

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                ForEach(pins) { pin in
                    Annotation("", coordinate: pin.coordinate, anchor: .bottom) {
                        priceBadge(pin, isSelected: selected?.id == pin.id)
                            .onTapGesture { withAnimation(.snappy(duration: 0.24)) { selected = pin } }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .ignoresSafeArea(edges: .bottom)
            .onTapGesture { withAnimation(.snappy(duration: 0.2)) { selected = nil } }

            if isResolving {
                notice(KXListingCopy.pickText(language, "正在定位房源…", "位置を解決中…", "Locating results…"), spinner: true)
            } else if pins.isEmpty {
                notice(KXListingCopy.pickText(language, "这些结果暂时无法在地图显示", "地図に表示できる結果がありません", "These results can't be mapped yet"), spinner: false)
            }

            if let selected {
                VStack {
                    Spacer()
                    selectedCard(selected)
                        .padding(.horizontal, KXSpacing.screen)
                        .padding(.bottom, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .task(id: listings.map(\.id)) { await resolve() }
    }

    // MARK: pins

    private func priceBadge(_ pin: ListingMapPin, isSelected: Bool) -> some View {
        Text(KXListingCopy.priceLabel(pin.listing, language))
            .font(.caption.weight(.black))
            .foregroundStyle(isSelected ? KXColor.onAccent : KXColor.livingInk)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(isSelected ? KXColor.livingAccent : KXColor.livingSurface, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : KXColor.livingInk.opacity(0.12), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .scaleEffect(isSelected ? 1.08 : 1)
    }

    private func notice(_ text: String, spinner: Bool) -> some View {
        HStack(spacing: KXSpacing.sm) {
            if spinner { KXSpinner(size: 16, lineWidth: 2.2) }
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.livingInk)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(KXColor.livingInk.opacity(0.08), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.top, KXSpacing.md)
    }

    private func selectedCard(_ pin: ListingMapPin) -> some View {
        Button { onOpen(pin.id) } label: {
            HStack(spacing: KXSpacing.md) {
                cover(pin.listing)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    Text(KXListingCopy.priceLabel(pin.listing, language))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(KXColor.livingWarm)
                        .lineLimit(1)
                    Text(KXListingCopy.displayTitle(pin.listing))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let loc = pin.listing.location_text, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .kxLivingSurface(radius: KXRadius.card, elevated: true)
        }
        .buttonStyle(KXPressableStyle())
    }

    @ViewBuilder
    private func cover(_ listing: KaiXCityListingDTO) -> some View {
        if let url = listing.realCoverURL {
            CachedMediaImageView(url: url, targetPixelSize: 240, failureMode: .transparent)
        } else {
            ZStack {
                KXColor.livingSoft
                Image(systemName: KXListingCopy.icon(for: listing.type))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
    }

    // MARK: geocoding

    /// Cleanest geocodable signal: prefer a station name, else the location
    /// text, with trailing noise ("步行7分钟", separators) trimmed; scoped to
    /// Japan for disambiguation.
    private func query(for listing: KaiXCityListingDTO) -> String? {
        let station = KXListingCopy.attr(listing, "nearest_station") ?? KXListingCopy.attr(listing, "near_station")
        var raw = (station?.isEmpty == false ? station! : (listing.location_text ?? ""))
        for sep in ["步行", " · ", "·", "，", ",", "／", "/"] {
            if let r = raw.range(of: sep) { raw = String(raw[..<r.lowerBound]) }
        }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return cleaned + " 日本"
    }

    private func resolve() async {
        isResolving = true
        var resolved: [ListingMapPin] = []
        var coordUse: [String: Int] = [:]   // 相同坐标出现次数 → 环形散开
        // Cap the work so a huge result set doesn't hammer the geocoder.
        for listing in listings.prefix(40) {
            // .task(id:) 换筛选会启动新循环——旧循环必须立刻让位,否则两个
            // 循环并发打 CLGeocoder,还会用旧列表的结果覆盖新 pins。
            if Task.isCancelled { return }
            guard let q = query(for: listing) else { continue }
            guard let coord = await ListingGeocodeCache.shared.resolve(q) else { continue }
            if Task.isCancelled { return }
            let key = String(format: "%.5f,%.5f", coord.latitude, coord.longitude)
            let dup = coordUse[key, default: 0]
            coordUse[key] = dup + 1
            resolved.append(ListingMapPin(id: listing.id, coordinate: Self.displacedCoordinate(coord, index: dup), listing: listing))
            pins = resolved   // progressive reveal as pins land
        }
        guard !Task.isCancelled else { return }
        pins = resolved
        isResolving = false
    }

    /// 同一车站的房源 geocode 出完全相同的坐标,pin 全叠一点只剩最顶层可点,
    /// 「新宿站步行5分钟」的 15 套房在地图上只见 1 个价签。按重复序号做确定性
    /// 小偏移(每圈 8 个、约 55m 递增),首个保持原坐标,全部可见可点。
    private static func displacedCoordinate(_ coord: CLLocationCoordinate2D, index: Int) -> CLLocationCoordinate2D {
        guard index > 0 else { return coord }
        let ring = (index - 1) / 8 + 1
        let slot = (index - 1) % 8
        let angle = Double(slot) * (.pi / 4) + Double(ring - 1) * (.pi / 8)
        let radius = 0.0005 * Double(ring)   // ≈55m / 圈
        let latScale = max(0.2, cos(coord.latitude * .pi / 180))
        return CLLocationCoordinate2D(
            latitude: coord.latitude + radius * sin(angle),
            longitude: coord.longitude + radius * cos(angle) / latScale
        )
    }
}
