import SwiftUI

/// Seller-side management list: everything the current user has posted to
/// the city marketplace (secondhand / rental / job / service / discount),
/// including non-published states, newest first. Rows route into the
/// regular listing detail where edit/manage actions live.
struct MyCityListingsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    let currentUser: UserEntity

    @State private var listings: [KaiXCityListingDTO] = []
    @State private var state: ScreenState = .idle

    private static let managedTypes = ["secondhand", "rental", "job", "local_service", "discount"]

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                KXInlineLoader()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ErrorStateView(message: message) { Task { await load() } }
            case .empty:
                EmptyStateView(
                    title: "还没有发布过城市信息",
                    subtitle: "二手、租房、招聘和本地服务的发布都会出现在这里。",
                    systemImage: "tray"
                )
            case .loaded:
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(listings) { listing in
                            Button {
                                router.open(.cityListingDetail(listingId: listing.id))
                            } label: {
                                row(listing)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
                    .padding(.vertical, 10)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("我的城市发布")
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .task { await load() }
    }

    private func row(_ listing: KaiXCityListingDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(listing.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    statusChip(listing.status)
                    Text(typeLabel(listing.type))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let updated = listing.updated_at ?? listing.updatedAt, !updated.isEmpty {
                        Text(String(updated.prefix(10)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
        .contentShape(Rectangle())
    }

    private func statusChip(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "published": ("已发布", .green)
        case "reserved": ("已预订", .orange)
        case "sold", "closed": ("已结束", .secondary)
        case "pending_review", "reviewing": ("审核中", .blue)
        case "rejected": ("未通过", .red)
        case "draft": ("草稿", .secondary)
        default: (status, .secondary)
        }
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "secondhand": "二手"
        case "rental": "租房"
        case "job": "招聘"
        case "local_service": "本地服务"
        case "discount": "优惠"
        default: type
        }
    }

    private func load() async {
        if listings.isEmpty { state = .loading }
        guard KaiXBackend.token != nil else {
            state = .empty
            return
        }
        do {
            let results = try await withThrowingTaskGroup(of: [KaiXCityListingDTO].self) { group in
                for type in Self.managedTypes {
                    group.addTask { try await KaiXAPIClient.shared.myListings(type: type) }
                }
                var merged: [KaiXCityListingDTO] = []
                for try await page in group { merged.append(contentsOf: page) }
                return merged
            }
            var seen = Set<String>()
            listings = results
                .filter { seen.insert($0.id).inserted }
                .sorted { ($0.updated_at ?? $0.updatedAt ?? "") > ($1.updated_at ?? $1.updatedAt ?? "") }
            state = listings.isEmpty ? .empty : .loaded
        } catch {
            state = listings.isEmpty ? .error(error.kaixUserMessage) : .loaded
        }
    }
}
