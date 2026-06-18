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
    @State private var pendingDelete: KaiXCityListingDTO?
    @State private var actionMessage: String?
    @State private var isActing = false

    private static let managedTypes = ["secondhand", "rental", "job", "hiring", "local_service", "discount"]

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
                    title: L("workbenchCityListingsEmpty", language),
                    subtitle: L("workbenchCityListingsEmptyHelp", language),
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
                            .contextMenu {
                                Button {
                                    router.open(.editCityListing(listingId: listing.id))
                                } label: {
                                    Label(L("edit", language), systemImage: "pencil")
                                }
                                if listing.status == "hidden" || listing.status == "draft" {
                                    Button {
                                        Task { await updateStatus(listing, status: "published") }
                                    } label: {
                                        Label(L("listingRepublish", language), systemImage: "arrow.up.circle")
                                    }
                                } else if listing.status == "published" || listing.status == "reserved" {
                                    Button {
                                        Task { await updateStatus(listing, status: "hidden") }
                                    } label: {
                                        Label(L("listingHideTemporarily", language), systemImage: "eye.slash")
                                    }
                                    Button {
                                        Task { await updateStatus(listing, status: completionStatus(for: listing)) }
                                    } label: {
                                        Label(completionLabel(for: listing), systemImage: "checkmark.circle")
                                    }
                                }
                                Button(role: .destructive) {
                                    pendingDelete = listing
                                } label: {
                                    Label(L("delete", language), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = listing
                                } label: {
                                    Label(L("delete", language), systemImage: "trash")
                                }
                                Button {
                                    router.open(.editCityListing(listingId: listing.id))
                                } label: {
                                    Label(L("edit", language), systemImage: "pencil")
                                }
                                .tint(KXColor.accent)
                            }
                        }
                    }
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
                    .padding(.top, 10)
                    .kxTabBarSafeBottomPadding()
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle(L("workbenchCityListingsTitle", language))
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .task { await load() }
        .overlay(alignment: .bottom) {
            if let actionMessage {
                Text(actionMessage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.black.opacity(0.78), in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert(L("listingDeleteConfirmTitle", language), isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(L("cancel", language), role: .cancel) { pendingDelete = nil }
            Button(L("delete", language), role: .destructive) {
                guard let listing = pendingDelete else { return }
                pendingDelete = nil
                Task { await delete(listing) }
            }
        } message: {
            Text(L("listingDeleteConfirmMessage", language))
        }
        .disabled(isActing)
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
        case "published": (L("status_active", language), .green)
        case "reserved": (L("status_reserved", language), .orange)
        case "hidden": (L("listingStatusHidden", language), .secondary)
        case "rented": (L("status_rented", language), .secondary)
        case "sold", "closed": (L("listingStatusClosed", language), .secondary)
        case "pending_review", "reviewing": (L("status_under_review", language), .blue)
        case "rejected": (L("listingStatusRejected", language), .red)
        case "draft": (L("listingStatusDraft", language), .secondary)
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
        case "secondhand": L("secondhand", language)
        case "rental": L("housing", language)
        case "job": L("ct_jobpost", language)
        case "hiring": L("ct_jobpost", language)
        case "local_service": L("ct_service", language)
        case "discount": L("ct_coupon", language)
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

    private func completionStatus(for listing: KaiXCityListingDTO) -> String {
        listing.type == "rental" ? "rented" : listing.type == "secondhand" ? "sold" : "closed"
    }

    private func completionLabel(for listing: KaiXCityListingDTO) -> String {
        listing.type == "rental" ? L("listingMarkRented", language) : listing.type == "secondhand" ? L("listingMarkSold", language) : L("listingMarkClosed", language)
    }

    private func updateStatus(_ listing: KaiXCityListingDTO, status: String) async {
        guard !isActing else { return }
        isActing = true
        defer { isActing = false }
        do {
            let updated = try await KaiXAPIClient.shared.updateListingStatus(listing.id, status: status)
            if let index = listings.firstIndex(where: { $0.id == listing.id }) {
                listings[index] = updated
            }
            showActionMessage(status == "hidden" ? L("listingHiddenDone", language) : status == "published" ? L("listingRepublishedDone", language) : L("listingStatusUpdated", language))
        } catch {
            showActionMessage(error.kaixUserMessage)
        }
    }

    private func delete(_ listing: KaiXCityListingDTO) async {
        guard !isActing else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await KaiXAPIClient.shared.deleteListing(listing.id)
            withAnimation(.easeOut(duration: 0.2)) {
                listings.removeAll { $0.id == listing.id }
                if listings.isEmpty { state = .empty }
            }
            showActionMessage(L("listingDeletedDone", language))
        } catch {
            showActionMessage(error.kaixUserMessage)
        }
    }

    private func showActionMessage(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            actionMessage = text
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.18)) {
                if actionMessage == text { actionMessage = nil }
            }
        }
    }
}
