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

/// Viewport bounding box handed to the「搜索此区域」closure.
struct KXMapBoundingBox {
    let minLat: Double
    let maxLat: Double
    let minLng: Double
    let maxLng: Double

    init(region: MKCoordinateRegion) {
        let halfLat = region.span.latitudeDelta / 2
        let halfLng = region.span.longitudeDelta / 2
        minLat = region.center.latitude - halfLat
        maxLat = region.center.latitude + halfLat
        minLng = region.center.longitude - halfLng
        maxLng = region.center.longitude + halfLng
    }
}

struct ListingMapPin: Identifiable {
    /// 一枚 pin 的数据来源:进频道时的列表条目(完整 DTO),或「搜索此区域」
    /// 重查返回的轻量服务端 pin(只有标题/价格/坐标)。
    enum Content {
        case listing(KaiXCityListingDTO)
        case remote(KaiXListingMapPinDTO)
    }

    let id: String
    let coordinate: CLLocationCoordinate2D
    let content: Content
}

/// Airbnb-style map of the current results. Pins are price badges; tapping one
/// raises a compact card that opens the detail. 服务端下发坐标的条目直接上图
/// (无 40 条上限);无坐标的回退设备端 geocode,coverage depends on how cleanly
/// each listing's location geocodes — unmappable ones are simply omitted.
/// 提供 `searchArea` 闭包后,地图被用户拖动/缩放会浮出「搜索此区域」胶囊,
/// 按当前取景框 bbox 重查并整体替换 pin(服务端 pin 自带坐标,无条数上限)。
struct ListingMapView: View {
    @Environment(\.appLanguage) private var language
    let listings: [KaiXCityListingDTO]
    let onOpen: (String) -> Void
    /// 「搜索此区域」重查闭包(nil = 隐藏该功能)。入参为当前取景框 bbox,
    /// 返回服务端 pins 页;抛错时降级为「暂不可用」提示,pin 保持原样。
    var searchArea: ((KXMapBoundingBox) async throws -> KaiXAPIClient.ListingPinsPage)? = nil
    /// 远端 pin 价格标签的类型语境(rental → 自动补「/月」等);pins 契约
    /// 不带 price_type/currency,按频道类型给默认量纲。
    var searchAreaListingType: String = "rental"

    @State private var pins: [ListingMapPin] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: ListingMapPin?
    @State private var isResolving = true
    /// 最近一次成功 resolve 的列表 id 签名(pop-back 的同 id 重放据此跳过,
    /// 见 resolve() 头注)。
    @State private var resolvedSignature = ""
    /// 当前取景框(onMapCameraChange 持续回写),area 搜索按它算 bbox。
    @State private var visibleRegion: MKCoordinateRegion?
    /// 用户拖动/缩放过地图 → 浮出「搜索此区域」;搜索完成后收起,再动再出。
    @State private var areaSearchArmed = false
    /// 自增触发器:每点一次「搜索此区域」+1,`.task(id:)` 自动取消旧请求。
    @State private var areaSearchToken = 0
    @State private var isAreaSearching = false
    /// true = 当前 pins 来自「搜索此区域」重查(空结果文案与列表模式不同)。
    @State private var pinsFromAreaSearch = false
    /// 已消化到哪个 token:`.task(id:)` 在 pop-back 重新挂载时会带旧 id 再跑
    /// 一遍,若不记账,从详情页返回地图就会凭空重发一次 area 请求。
    @State private var consumedAreaSearchToken = 0
    /// 「搜索此区域」失败的瞬时提示(约 2.6s 自动消失)。
    @State private var areaSearchNotice: String?

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
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                // 初次自动取景也会回调;只有用户亲手挪过相机才浮出胶囊。
                if position.positionedByUser, searchArea != nil, !areaSearchArmed {
                    withAnimation(.snappy(duration: 0.24)) { areaSearchArmed = true }
                }
            }

            VStack(spacing: KXSpacing.sm) {
                if isResolving {
                    notice(KXListingCopy.pickText(language, "正在定位房源…", "位置を解決中…", "Locating results…"), spinner: true)
                } else if pins.isEmpty, pinsFromAreaSearch {
                    notice(KXListingCopy.pickText(language, "此区域暂无相关内容", "このエリアには該当がありません", "Nothing in this area yet"), spinner: false)
                } else if pins.isEmpty {
                    notice(KXListingCopy.pickText(language, "这些结果暂时无法在地图显示", "地図に表示できる結果がありません", "These results can't be mapped yet"), spinner: false)
                }
                if searchArea != nil, areaSearchArmed || isAreaSearching {
                    areaSearchPill
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let areaSearchNotice {
                    notice(areaSearchNotice, spinner: false)
                        .transition(.opacity)
                        .task {
                            try? await Task.sleep(for: .seconds(2.6))
                            guard !Task.isCancelled else { return }
                            withAnimation(.snappy(duration: 0.2)) { self.areaSearchNotice = nil }
                        }
                }
            }
            .padding(.top, KXSpacing.md)

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
        .task(id: areaSearchToken) {
            // 0 = 首次挂载;<= 已消化值 = pop-back 的同 id 重放,都不发请求。
            guard areaSearchToken > consumedAreaSearchToken else { return }
            await performAreaSearch()
            // 失败也记账:从详情页返回不该自动重试一次失败的搜索。被取消
            // (中途导航走)则不记账,回来后补跑完成未竟的那次搜索。
            if !Task.isCancelled { consumedAreaSearchToken = areaSearchToken }
        }
    }

    // MARK: area search

    /// 浮动「搜索此区域」胶囊,与顶部 notice 同一材质/描边/投影语汇。
    private var areaSearchPill: some View {
        Button { areaSearchToken += 1 } label: {
            HStack(spacing: KXSpacing.xs) {
                if isAreaSearching {
                    KXSpinner(size: 14, lineWidth: 2)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.caption.weight(.bold))
                }
                Text(KXListingCopy.pickText(language, "搜索此区域", "このエリアを検索", "Search this area"))
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(KXColor.livingInk)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(KXColor.livingInk.opacity(0.08), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(KXPressableStyle(scale: 0.95))
        .disabled(isAreaSearching)
    }

    private func performAreaSearch() async {
        guard let searchArea, let region = visibleRegion else { return }
        isAreaSearching = true
        defer { isAreaSearching = false }
        do {
            let page = try await searchArea(KXMapBoundingBox(region: region))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.24)) {
                selected = nil
                pinsFromAreaSearch = true
                isResolving = false
                pins = Self.spread(remote: page.pins)
                areaSearchArmed = false
            }
        } catch {
            // 导航/新一轮搜索的取消不是可行动错误;其余(旧服务端 400、pins
            // 契约缺失、网络问题)统一降级成瞬时「暂不可用」,原 pin 不动。
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2)) {
                areaSearchNotice = KXListingCopy.pickText(language, "「搜索此区域」暂不可用", "「このエリアを検索」は現在利用できません", "Area search isn't available right now")
            }
        }
    }

    /// 服务端 pins → 地图 pin:合法坐标直接上图(无条数预算),同点重复
    /// 沿用环形散开,保证全部可见可点。
    private static func spread(remote: [KaiXListingMapPinDTO]) -> [ListingMapPin] {
        var coordUse: [String: Int] = [:]
        var result: [ListingMapPin] = []
        for pin in remote {
            guard abs(pin.latitude) <= 90, abs(pin.longitude) <= 180,
                  !(pin.latitude == 0 && pin.longitude == 0) else { continue }
            let coord = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
            let key = String(format: "%.5f,%.5f", coord.latitude, coord.longitude)
            let dup = coordUse[key, default: 0]
            coordUse[key] = dup + 1
            result.append(ListingMapPin(id: pin.id, coordinate: Self.displacedCoordinate(coord, index: dup), content: .remote(pin)))
        }
        return result
    }

    // MARK: pins

    /// 价签文案:完整 DTO 走既有 priceLabel;远端 pin 只有裸价,按频道类型
    /// 补默认量纲(rental → /月)。
    private func priceText(_ pin: ListingMapPin) -> String {
        switch pin.content {
        case .listing(let listing):
            return KXListingCopy.priceLabel(listing, language)
        case .remote(let remote):
            return KXListingCopy.formatPrice(price: remote.price, currency: nil, priceType: nil, type: searchAreaListingType, language)
        }
    }

    private func pinTitle(_ pin: ListingMapPin) -> String {
        switch pin.content {
        case .listing(let listing):
            return KXListingCopy.displayTitle(listing)
        case .remote(let remote):
            let title = (remote.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? KXListingCopy.pickText(language, "查看详情", "詳細を見る", "View details") : title
        }
    }

    private func priceBadge(_ pin: ListingMapPin, isSelected: Bool) -> some View {
        Text(priceText(pin))
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
        // 顶部间距由容器 VStack 统一给(notice 与「搜索此区域」胶囊纵向排列)。
    }

    private func selectedCard(_ pin: ListingMapPin) -> some View {
        Button { onOpen(pin.id) } label: {
            HStack(spacing: KXSpacing.md) {
                cover(pin)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    Text(priceText(pin))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(KXColor.livingWarm)
                        .lineLimit(1)
                    Text(pinTitle(pin))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if case .listing(let listing) = pin.content,
                       let loc = listing.location_text, !loc.isEmpty {
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
    private func cover(_ pin: ListingMapPin) -> some View {
        // 远端 pin 无媒体字段,恒走占位图;完整 DTO 有真实封面才加载。
        if case .listing(let listing) = pin.content, let url = listing.realCoverURL {
            CachedMediaImageView(url: url, targetPixelSize: 240, failureMode: .transparent)
        } else {
            ZStack {
                KXColor.livingSoft
                Image(systemName: KXListingCopy.icon(for: coverIconType(pin)))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
    }

    private func coverIconType(_ pin: ListingMapPin) -> String {
        switch pin.content {
        case .listing(let listing): listing.type
        case .remote: searchAreaListingType
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
        // .task(id:) 在 pop-back 重新挂载时会带同一个 id 再跑——列表没变而
        // 屏上是「搜索此区域」的结果时,这次重放是无效重解析,还会把用户刚
        // 搜出来的区域 pin 悄悄换回列表 pin;直接跳过(与频道 loadedSignature
        // 同一思路)。列表真变了(筛选/翻页)才回到「列表结果上图」语义。
        let signature = listings.map(\.id).joined(separator: "|")
        if pinsFromAreaSearch, signature == resolvedSignature { return }
        isResolving = true
        pinsFromAreaSearch = false
        var resolved: [ListingMapPin] = []
        var coordUse: [String: Int] = [:]   // 相同坐标出现次数 → 环形散开
        // 服务端坐标(partner 房源自带精确经纬度)不占预算、全量上图;只有
        // 无坐标的条目才回退 CLGeocoder,预算 40 次防止大结果集打爆限流。
        var geocodeBudget = 40
        for listing in listings {
            // .task(id:) 换筛选会启动新循环——旧循环必须立刻让位,否则两个
            // 循环并发打 CLGeocoder,还会用旧列表的结果覆盖新 pins。中途
            // 完成的「搜索此区域」同理:区域 pin 已上图,本循环立即让位,
            // 不再用列表 pin 覆盖。
            if Task.isCancelled || pinsFromAreaSearch { return }
            let coord: CLLocationCoordinate2D?
            if let lat = listing.latitude, let lng = listing.longitude,
               abs(lat) <= 90, abs(lng) <= 180, !(lat == 0 && lng == 0) {
                coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            } else if geocodeBudget > 0, let q = query(for: listing) {
                geocodeBudget -= 1
                coord = await ListingGeocodeCache.shared.resolve(q)
                if Task.isCancelled || pinsFromAreaSearch { return }
            } else {
                coord = nil
            }
            guard let coord else { continue }
            let key = String(format: "%.5f,%.5f", coord.latitude, coord.longitude)
            let dup = coordUse[key, default: 0]
            coordUse[key] = dup + 1
            resolved.append(ListingMapPin(id: listing.id, coordinate: Self.displacedCoordinate(coord, index: dup), content: .listing(listing)))
            pins = resolved   // progressive reveal as pins land
        }
        guard !Task.isCancelled, !pinsFromAreaSearch else { return }
        pins = resolved
        isResolving = false
        resolvedSignature = signature
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
