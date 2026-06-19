import Foundation
import SwiftData

@MainActor
final class PostRepository {
    private let context: ModelContext
    private let heatService: HeatScoreService

    init(context: ModelContext) {
        self.context = context
        self.heatService = .shared
    }

    /// SwiftData's `fetchOffset` silently returns the FIRST window again on
    /// current iOS releases (observed on iOS 26 with sort descriptors set:
    /// the offset is ignored), which made every local "page" identical —
    /// the home/city feeds visibly looped the same posts. Page by fetching
    /// `(page+1) * pageSize` rows and slicing in memory instead: the local
    /// cache is small (hundreds of rows), so the linear over-fetch is cheap
    /// and, unlike fetchOffset, deterministic everywhere.
    private func fetchWindow(_ descriptor: FetchDescriptor<PostEntity>, page: Int, pageSize: Int) throws -> [PostEntity] {
        var d = descriptor
        d.fetchOffset = 0
        d.fetchLimit = (page + 1) * pageSize
        let rows = try context.fetch(d)
        guard rows.count > page * pageSize else { return [] }
        return Array(rows.dropFirst(page * pageSize))
    }

    private func fetchLegacyLocationlessWindow(
        published: String,
        active: String,
        page: Int,
        pageSize: Int,
        sortDescriptors: [SortDescriptor<PostEntity>],
        recentCutoff: Date? = nil,
        typeRaws: [String] = []
    ) throws -> [PostEntity] {
        let emptyLocation = ""
        let descriptor = FetchDescriptor<PostEntity>(
            predicate: #Predicate {
                ($0.statusRaw == published || $0.statusRaw == active)
                && $0.regionCode == emptyLocation
                && $0.country == emptyLocation
                && $0.city == emptyLocation
            },
            sortBy: sortDescriptors
        )
        let rows = try fetchWindow(descriptor, page: page, pageSize: pageSize * 3)
        return Array(rows.filter { post in
            let matchesRecent = recentCutoff.map { post.createdAt >= $0 } ?? true
            let matchesType = typeRaws.isEmpty || typeRaws.contains(post.contentTypeRaw)
            return matchesRecent && matchesType
        }.prefix(pageSize))
    }

    func fetchPage(mode: TimelineMode, currentUserId: String, page: Int, pageSize: Int) async throws -> [PostEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let apiMode: KaiXAPIClient.FeedMode
            switch mode {
            case .recommend: apiMode = .recommend
            case .local: apiMode = .local
            case .following: apiMode = .following
            case .hot: apiMode = .hot
            }
            let region = await MainActor.run { RegionStore.shared.current }
            let response = try await KaiXAPIClient.shared.feed(
                mode: apiMode,
                regionCode: mode == .local ? region?.regionCode : nil,
                country: region?.countryCode,
                province: mode == .local ? (region?.provinceCode.isEmpty == true ? nil : region?.provinceCode) : nil,
                city: mode == .local ? region?.cityCode : nil
            )
            return ServerEntityFactory.postBundle(from: response.items).orderedPosts
        }
        let published = PostStatus.published.rawValue
        let active = PostStatus.active.rawValue
        // The trailing `id` tiebreaker is load-bearing: bulk-seeded and
        // editorial posts share identical createdAt timestamps, and SQLite
        // returns equal-key rows in arbitrary, per-query order. Without a
        // total order, offset windows shuffle between fetches and the feed
        // visibly repeats/skips posts while paging.
        let sortDescriptors: [SortDescriptor<PostEntity>] = mode == .hot
            ? [SortDescriptor(\.heatScore, order: .reverse), SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.id, order: .reverse)]
            : [SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.id, order: .reverse)]
        let recentCutoff = Date().addingTimeInterval(-10 * 24 * 3600)

        var descriptor = FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.statusRaw == published || $0.statusRaw == active },
            sortBy: sortDescriptors
        )

        // Ranking context — captures the user's region + content
        // language preferences and is applied in-memory below to the
        // fetched page so a language switch reshuffles the deck without
        // needing every SwiftData predicate to grow a "language IN (…)"
        // arm that #Predicate can't easily express.
        let appLang = await MainActor.run(body: { AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? "") })
        let ranking = await MainActor.run(body: { FeedQueryBuilder.context(for: appLang) })
        let selectedCountry = ranking.region?.countryCode ?? ""
        // Every mode pages over DISJOINT createdAt-ordered windows
        // (offset = page * pageSize, limit = pageSize). The in-memory
        // ranking below only reorders WITHIN the fetched window. The old
        // "over-fetch 2x then keep the best half" trick made window N
        // overlap window N+1 by a full page, so posts the ranking had
        // already surfaced came back on the next page — the visible
        // symptom was the home feed looping the same posts forever.
        let limit = pageSize

        if mode == .following {
            let followIds = try followingIds(for: currentUserId)
            let authorIds = Array(followIds.union([currentUserId]))
            if selectedCountry.isEmpty {
                descriptor.predicate = #Predicate {
                    ($0.statusRaw == published || $0.statusRaw == active) && authorIds.contains($0.authorId)
                }
            } else {
                descriptor.predicate = #Predicate {
                    ($0.statusRaw == published || $0.statusRaw == active)
                    && authorIds.contains($0.authorId)
                    && $0.country == selectedCountry
                }
            }
            let pagePosts = try fetchWindow(descriptor, page: page, pageSize: pageSize)
            try refreshRepostState(for: pagePosts, currentUserId: currentUserId)
            return FeedQueryBuilder.rank(pagePosts, using: ranking)
        }

        if mode == .local {
            // Same-city stream. If the user hasn't picked a region yet
            // we return an empty page so the UI can prompt them — the
            // server-side `local` mode would 400 in the same case.
            guard let region = await MainActor.run(body: { RegionStore.shared.current }) else {
                return []
            }
            let regionCodes = KaiXRegionDirectory.regionCodesForMetro(region: region)
            let country = region.countryCode
            let cityCodes = KaiXRegionDirectory.cityCodesForMetro(region: region)
            descriptor.predicate = #Predicate {
                ($0.statusRaw == published || $0.statusRaw == active)
                && (regionCodes.contains($0.regionCode) || ($0.country == country && cityCodes.contains($0.city)))
            }
            var pagePosts = try fetchWindow(descriptor, page: page, pageSize: limit)
            if page == 0 && pagePosts.isEmpty {
                pagePosts = try fetchLegacyLocationlessWindow(
                    published: published,
                    active: active,
                    page: page,
                    pageSize: limit,
                    sortDescriptors: sortDescriptors
                )
            }
            try refreshRepostState(for: pagePosts, currentUserId: currentUserId)
            return FeedQueryBuilder.rank(pagePosts, using: ranking)
        }

        if mode == .hot {
            if let selectedRegion = ranking.region {
                let regionCodes = KaiXRegionDirectory.regionCodesForMetro(region: selectedRegion)
                let cityCodes = KaiXRegionDirectory.cityCodesForMetro(region: selectedRegion)
                let country = selectedRegion.countryCode
                descriptor.predicate = #Predicate {
                    ($0.statusRaw == published || $0.statusRaw == active)
                    && $0.createdAt >= recentCutoff
                    && (regionCodes.contains($0.regionCode) || ($0.country == country && cityCodes.contains($0.city)))
                }
            } else if selectedCountry.isEmpty {
                descriptor.predicate = #Predicate {
                    ($0.statusRaw == published || $0.statusRaw == active) && $0.createdAt >= recentCutoff
                }
            } else {
                descriptor.predicate = #Predicate {
                    ($0.statusRaw == published || $0.statusRaw == active)
                    && $0.createdAt >= recentCutoff
                    && $0.country == selectedCountry
                }
            }
            var pagePosts = try fetchWindow(descriptor, page: page, pageSize: pageSize)
            if page == 0 && pagePosts.isEmpty {
                pagePosts = try fetchLegacyLocationlessWindow(
                    published: published,
                    active: active,
                    page: page,
                    pageSize: pageSize,
                    sortDescriptors: sortDescriptors,
                    recentCutoff: recentCutoff
                )
            }
            try refreshRepostState(for: pagePosts, currentUserId: currentUserId)
            return FeedQueryBuilder.rank(pagePosts, using: ranking)
        }

        // recommend
        if !selectedCountry.isEmpty {
            descriptor.predicate = #Predicate {
                ($0.statusRaw == published || $0.statusRaw == active)
                && $0.country == selectedCountry
            }
        }
        let posts = try fetchWindow(descriptor, page: page, pageSize: limit)
        try refreshRepostState(for: posts, currentUserId: currentUserId)
        return FeedQueryBuilder.rank(posts, using: ranking)
    }

    func fetchCityPage(
        region: KaiXRegionDirectory.Region,
        channel: CityChannel,
        currentUserId: String,
        page: Int,
        pageSize: Int
    ) async throws -> [PostEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let response = try await KaiXAPIClient.shared.feed(
                mode: channel == .hot ? .hot : .recommend,
                regionCode: region.regionCode,
                country: region.countryCode,
                province: region.provinceCode.isEmpty ? nil : region.provinceCode,
                city: region.cityCode,
                contentTypes: channel.contentTypes
            )
            return ServerEntityFactory.postBundle(from: response.items).orderedPosts
        }
        let published = PostStatus.published.rawValue
        let active = PostStatus.active.rawValue
        let regionCodes = KaiXRegionDirectory.regionCodesForMetro(region: region)
        let country = region.countryCode
        let cityCodes = KaiXRegionDirectory.cityCodesForMetro(region: region)
        let typeRaws = channel.contentTypes?.map(\.rawValue) ?? []
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        // Same total-order requirement as fetchPage: equal-timestamp rows
        // shuffle between queries without the id tiebreaker, which makes
        // offset windows repeat posts while paging.
        let sortDescriptors: [SortDescriptor<PostEntity>] = channel.sortsByHeat
            ? [SortDescriptor(\.heatScore, order: .reverse), SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.id, order: .reverse)]
            : [SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.id, order: .reverse)]

        var descriptor: FetchDescriptor<PostEntity>
        if !typeRaws.isEmpty && channel.limitsToRecentHotWindow {
            descriptor = FetchDescriptor<PostEntity>(
                predicate: #Predicate {
                    ($0.statusRaw == published || $0.statusRaw == active)
                    && (regionCodes.contains($0.regionCode) || ($0.country == country && cityCodes.contains($0.city)))
                    && typeRaws.contains($0.contentTypeRaw)
                    && $0.createdAt >= cutoff
                },
                sortBy: sortDescriptors
            )
        } else if !typeRaws.isEmpty {
            descriptor = FetchDescriptor<PostEntity>(
                predicate: #Predicate {
                    ($0.statusRaw == published || $0.statusRaw == active)
                    && (regionCodes.contains($0.regionCode) || ($0.country == country && cityCodes.contains($0.city)))
                    && typeRaws.contains($0.contentTypeRaw)
                },
                sortBy: sortDescriptors
            )
        } else if channel.limitsToRecentHotWindow {
            descriptor = FetchDescriptor<PostEntity>(
                predicate: #Predicate {
                    ($0.statusRaw == published || $0.statusRaw == active)
                    && (regionCodes.contains($0.regionCode) || ($0.country == country && cityCodes.contains($0.city)))
                    && $0.createdAt >= cutoff
                },
                sortBy: sortDescriptors
            )
        } else {
            descriptor = FetchDescriptor<PostEntity>(
                predicate: #Predicate {
                    ($0.statusRaw == published || $0.statusRaw == active)
                    && (regionCodes.contains($0.regionCode) || ($0.country == country && cityCodes.contains($0.city)))
                },
                sortBy: sortDescriptors
            )
        }
        // Disjoint windows + within-window ranking only — see fetchWindow
        // for why offset-based windows repeated posts on-device.
        var posts = try fetchWindow(descriptor, page: page, pageSize: pageSize)
        if page == 0 && posts.isEmpty {
            posts = try fetchLegacyLocationlessWindow(
                published: published,
                active: active,
                page: page,
                pageSize: pageSize,
                sortDescriptors: sortDescriptors,
                recentCutoff: channel.limitsToRecentHotWindow ? cutoff : nil,
                typeRaws: typeRaws
            )
        }
        try refreshRepostState(for: posts, currentUserId: currentUserId)
        let appLang = await MainActor.run(body: { AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? "") })
        let ranking = await MainActor.run(body: { FeedQueryBuilder.context(for: appLang) })
        return FeedQueryBuilder.rank(posts, using: ranking)
    }

    func fetchPost(id: String, currentUserId: String? = nil) async throws -> PostEntity? {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            return ServerEntityFactory.post(from: try await KaiXAPIClient.shared.post(id))
        }
        var descriptor = FetchDescriptor<PostEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let post = try context.fetch(descriptor).first
        if let post, let currentUserId {
            try refreshRepostState(for: [post], currentUserId: currentUserId)
        }
        return post
    }

    func fetchPosts(ids: Set<String>, currentUserId: String? = nil) async throws -> [PostEntity] {
        guard !ids.isEmpty else { return [] }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            var result: [PostEntity] = []
            for id in ids {
                if let post = try? await fetchPost(id: id, currentUserId: currentUserId) {
                    result.append(post)
                }
            }
            return result
        }
        let idList = Array(ids)
        let published = PostStatus.published.rawValue
        let active = PostStatus.active.rawValue
        let posts = try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { idList.contains($0.id) && ($0.statusRaw == published || $0.statusRaw == active) }
        ))
        if let currentUserId {
            try refreshRepostState(for: posts, currentUserId: currentUserId)
        }
        return posts
    }

    func fetchPosts(authorId: String) async throws -> [PostEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let page = try await KaiXAPIClient.shared.userPosts(authorId, segment: .posts)
            return ServerEntityFactory.postBundle(from: page.items).orderedPosts
        }
        let published = PostStatus.published.rawValue
        let active = PostStatus.active.rawValue
        return try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.authorId == authorId && ($0.statusRaw == published || $0.statusRaw == active) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    func fetchMediaPosts(authorId: String) async throws -> [PostEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let page = try await KaiXAPIClient.shared.userPosts(authorId, segment: .media)
            return ServerEntityFactory.postBundle(from: page.items).orderedPosts
        }
        let authored = try await fetchPosts(authorId: authorId)
        let authoredMedia = try await fetchMedia(for: authored)
        return authored.filter { authoredMedia[$0.id]?.isEmpty == false }
    }

    func fetchDrafts(authorId: String) async throws -> [PostEntity] {
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            return []
        }
        let draft = PostStatus.draft.rawValue
        return try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.authorId == authorId && $0.statusRaw == draft },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
    }

    func fetchPosts(topic: String) async throws -> [PostEntity] {
        let normalized = topic.normalizedTopicName
        guard !normalized.isEmpty else { return [] }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            return ServerEntityFactory.postBundle(from: try await KaiXAPIClient.shared.topic(normalized)).orderedPosts
        }
        let published = PostStatus.published.rawValue
        let active = PostStatus.active.rawValue
        var descriptor = FetchDescriptor<PostEntity>(
            predicate: #Predicate { ($0.statusRaw == published || $0.statusRaw == active) && $0.hashtagsRaw.contains(normalized) },
            sortBy: [SortDescriptor(\.heatScore, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 300
        return try context.fetch(descriptor)
            .filter { $0.hashtags.contains(normalized) || $0.content.localizedCaseInsensitiveContains("#\(topic)") }
    }

    func fetchRepliedPosts(authorId: String) async throws -> [PostEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let page = try await KaiXAPIClient.shared.userReplyPosts(authorId)
            return ServerEntityFactory.postBundle(from: page.items).orderedPosts
        }
        let comments = try context.fetch(FetchDescriptor<CommentEntity>(
            predicate: #Predicate { $0.authorId == authorId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        var seen = Set<String>()
        var orderedIds: [String] = []
        for comment in comments where seen.insert(comment.postId).inserted {
            orderedIds.append(comment.postId)
        }

        guard orderedIds.isEmpty == false else { return [] }
        let idList = orderedIds
        let published = PostStatus.published.rawValue
        let active = PostStatus.active.rawValue
        let posts = try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { idList.contains($0.id) && ($0.statusRaw == published || $0.statusRaw == active) }
        ))
        let byId = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        return orderedIds.compactMap { byId[$0] }
    }

    func fetchLikedPosts() async throws -> [PostEntity] {
        try await fetchLikedPosts(userId: AuthService.shared.currentUserId)
    }

    func fetchLikedPosts(userId: String) async throws -> [PostEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            guard !userId.isEmpty else { return [] }
            let page = try await KaiXAPIClient.shared.userPosts(userId, segment: .likes)
            return ServerEntityFactory.postBundle(from: page.items).orderedPosts
        }
        let published = PostStatus.published.rawValue
        let active = PostStatus.active.rawValue
        return try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.isLikedByCurrentUser && ($0.statusRaw == published || $0.statusRaw == active) },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
    }

    func fetchBookmarkedPosts() async throws -> [PostEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let userId = AuthService.shared.currentUserId
            guard !userId.isEmpty else { return [] }
            let page = try await KaiXAPIClient.shared.userPosts(userId, segment: .bookmarks)
            return ServerEntityFactory.postBundle(from: page.items).orderedPosts
        }
        let published = PostStatus.published.rawValue
        let active = PostStatus.active.rawValue
        return try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.isBookmarkedByCurrentUser && ($0.statusRaw == published || $0.statusRaw == active) },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
    }

    func fetchMedia(postId: String) async throws -> [MediaEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let dto = try await KaiXAPIClient.shared.post(postId)
            return ServerEntityFactory.media(from: dto.media, postId: dto.id)
        }
        return try context.fetch(FetchDescriptor<MediaEntity>(
            predicate: #Predicate { $0.postId == postId },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    func fetchMedia(for posts: [PostEntity]) async throws -> [String: [MediaEntity]] {
        let ids = Set(posts.map(\.id))
        guard !ids.isEmpty else { return [:] }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            var result: [String: [MediaEntity]] = [:]
            for id in ids {
                result[id] = (try? await fetchMedia(postId: id)) ?? []
            }
            return result
        }
        let idList = Array(ids)
        let media = try context.fetch(FetchDescriptor<MediaEntity>(
            predicate: #Predicate { idList.contains($0.postId) },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        return Dictionary(grouping: media, by: \.postId)
    }

    func createPost(
        authorId: String,
        content: String,
        mediaDrafts: [MediaDraft],
        hashtags: [String] = [],
        region: KaiXRegionDirectory.Region? = nil,
        contentType: ContentType = .dynamic,
        attributes: [String: KaiXAttributeValue] = [:],
        language: String = "",
        uploadedMediaByDraftID: [String: KaiXMediaDTO] = [:],
        onMediaUploadState: ((String, UploadState, Double) -> Void)? = nil,
        onMediaUploaded: ((String, KaiXMediaDTO) -> Void)? = nil
    ) async throws -> PostEntity {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedHashtags = hashtags.normalizedDisplayHashtags.isEmpty ? trimmed.extractedHashtags : hashtags.normalizedDisplayHashtags
        // Typed content can legitimately have no body text — e.g. a
        // secondhand listing whose "content" is the typed fields. So
        // we keep the empty-body check only for the dynamic path.
        if contentType == .dynamic {
            guard trimmed.isEmpty == false || mediaDrafts.isEmpty == false || storedHashtags.isEmpty == false else {
                throw RepositoryError.validationFailed
            }
        }

        // Online compose is transactional from the user's perspective: upload
        // every media item first, create the server post, then mirror the
        // confirmed server row into SwiftData. A failed 9-image/video upload
        // therefore leaves no half-created local post that can poison the next
        // publish attempt.
        if KaiXBackend.token != nil {
            var mediaIds: [String] = []
            mediaIds.reserveCapacity(mediaDrafts.count)
            for draft in mediaDrafts {
                if let uploaded = uploadedMediaByDraftID[draft.id] {
                    mediaIds.append(uploaded.id)
                    onMediaUploadState?(draft.id, .uploaded, 1)
                    continue
                }
                onMediaUploadState?(draft.id, .uploading, 0)
                do {
                    let uploaded = try await UploadService.shared.upload(
                        draft: draft,
                        purpose: draft.type == .video ? "post_video" : "post_image",
                        entityType: "post"
                    ) { itemProgress in
                        onMediaUploadState?(draft.id, .uploading, min(max(itemProgress, 0), 1))
                    }
                    mediaIds.append(uploaded.id)
                    onMediaUploaded?(draft.id, uploaded)
                    onMediaUploadState?(draft.id, .uploaded, 1)
                } catch {
                    onMediaUploadState?(draft.id, .failed, 0)
                    throw error
                }
            }

            let remote = try await KaiXAPIClient.shared.createPost(
                content: trimmed,
                mediaIds: mediaIds,
                tags: storedHashtags,
                country: region?.countryCode,
                province: region?.provinceCode.isEmpty == true ? nil : region?.provinceCode,
                city: region?.cityCode,
                regionCode: region?.regionCode,
                contentType: contentType.rawValue,
                attributes: attributes.isEmpty ? nil : attributes
            )
            return ServerEntityFactory.post(from: remote)
        }

        let post = PostEntity(
            authorId: authorId,
            content: trimmed,
            status: mediaDrafts.isEmpty ? .published : .uploading,
            hashtags: storedHashtags,
            country: region?.countryCode ?? "",
            province: region?.provinceCode ?? "",
            city: region?.cityCode ?? "",
            regionCode: region?.regionCode ?? "",
            contentType: contentType,
            attributesRaw: Self.encodeAttributesLocal(attributes),
            language: language
        )
        context.insert(post)

        for draft in mediaDrafts {
            context.insert(MediaEntity(
                id: draft.id,
                postId: post.id,
                type: draft.type,
                localURL: draft.localURL.path,
                thumbnailURL: draft.thumbnailURL.path,
                width: draft.width,
                height: draft.height,
                duration: draft.duration,
                fileSize: draft.uploadFileSize,
                mimeType: draft.contentType,
                uploadState: .local,
                uploadProgress: 1
            ))
        }

        post.status = .published
        heatService.refresh(post)
        try rebuildTopics()
        try context.save()
        return post
    }

    /// Internal helper for write-through mirroring; resolves the local
    /// PostEntity by its locally-issued id.
    static func findLocalPost(id: String, in context: ModelContext) throws -> PostEntity? {
        var d = FetchDescriptor<PostEntity>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    /// Serialise a typed-attributes map to the canonical JSON string
    /// used both on disk (PostEntity.attributesRaw) and on the wire.
    /// Kept here so the repository and the sync layer agree on
    /// exactly the same encoding.
    static func encodeAttributesLocal(_ map: [String: KaiXAttributeValue]) -> String {
        guard !map.isEmpty else { return "" }
        var plain: [String: Any] = [:]
        for (k, v) in map {
            switch v.kind {
            case .string(let s): plain[k] = s
            case .double(let n): plain[k] = n
            case .bool(let b):   plain[k] = b
            case .json(let j):   plain[k] = j.foundationObject
            case .null:          continue
            }
        }
        guard !plain.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: plain, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    func saveDraft(
        authorId: String,
        content: String,
        mediaDrafts: [MediaDraft],
        hashtags: [String] = [],
        region: KaiXRegionDirectory.Region? = nil,
        contentType: ContentType = .dynamic,
        attributes: [String: KaiXAttributeValue] = [:],
        language: String = ""
    ) async throws -> PostEntity {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedHashtags = hashtags.normalizedDisplayHashtags.isEmpty ? trimmed.extractedHashtags : hashtags.normalizedDisplayHashtags
        guard trimmed.isEmpty == false || mediaDrafts.isEmpty == false || storedHashtags.isEmpty == false || attributes.isEmpty == false else {
            throw RepositoryError.validationFailed
        }

        let post = PostEntity(
            authorId: authorId,
            content: trimmed,
            status: .draft,
            hashtags: storedHashtags,
            country: region?.countryCode ?? "",
            province: region?.provinceCode ?? "",
            city: region?.cityCode ?? "",
            regionCode: region?.regionCode ?? "",
            contentType: contentType,
            attributesRaw: Self.encodeAttributesLocal(attributes),
            language: language
        )
        context.insert(post)

        for draft in mediaDrafts {
            context.insert(MediaEntity(
                id: draft.id,
                postId: post.id,
                type: draft.type,
                localURL: draft.localURL.path,
                thumbnailURL: draft.thumbnailURL.path,
                width: draft.width,
                height: draft.height,
                duration: draft.duration,
                fileSize: draft.uploadFileSize,
                mimeType: draft.contentType,
                uploadState: .local,
                uploadProgress: 1
            ))
        }

        try context.save()
        return post
    }

    func updateDraft(post: PostEntity, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let postId = post.id
        var mediaDescriptor = FetchDescriptor<MediaEntity>(
            predicate: #Predicate { $0.postId == postId }
        )
        mediaDescriptor.fetchLimit = 1
        let hasMedia = try context.fetch(mediaDescriptor).isEmpty == false
        guard trimmed.isEmpty == false || hasMedia else { throw RepositoryError.validationFailed }
        post.content = trimmed
        post.hashtags = trimmed.extractedHashtags
        post.updatedAt = .now
        try context.save()
    }

    func publishDraft(post: PostEntity) async throws {
        post.status = .published
        post.updatedAt = .now
        heatService.refresh(post)
        try rebuildTopics()
        try context.save()
    }

    func incrementView(post: PostEntity) async throws {
        let previousHeat = post.heatScore
        post.viewCount += 1
        try refreshHeatAndTopics(for: post, previousHeat: previousHeat)
        try context.save()
    }

    func toggleLike(post: PostEntity, currentUserId: String) async throws {
        try await setLike(post: post, isLiked: !post.isLikedByCurrentUser, currentUserId: currentUserId)
    }

    func setLike(
        post: PostEntity,
        isLiked: Bool,
        currentUserId: String,
        countAlreadyUpdated: Bool = false
    ) async throws {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            ServerEntityFactory.apply(try await KaiXAPIClient.shared.setLike(post.remoteId ?? post.id, isLiked), to: post)
            return
        }
        let likeDelta = isLiked ? 1 : -1
        let previousHeat = countAlreadyUpdated
            ? heatScore(for: post, likeDelta: likeDelta)
            : post.heatScore
        if !countAlreadyUpdated, post.isLikedByCurrentUser != isLiked {
            post.likeCount = max(0, post.likeCount + likeDelta)
        }
        post.isLikedByCurrentUser = isLiked
        try refreshHeatAndTopics(for: post, previousHeat: previousHeat)

        if isLiked && post.authorId != currentUserId && NotificationPreferenceService.isEnabled(.like, recipientUserId: post.authorId) {
            try upsertNotification(type: .like, actorId: currentUserId, targetPostId: post.id, content: "喜欢了你的帖子")
        }

        try context.save()
    }

    func toggleBookmark(post: PostEntity, currentUserId: String) async throws {
        try await setBookmark(post: post, isBookmarked: !post.isBookmarkedByCurrentUser, currentUserId: currentUserId)
    }

    func setBookmark(
        post: PostEntity,
        isBookmarked: Bool,
        currentUserId: String,
        countAlreadyUpdated: Bool = false
    ) async throws {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            ServerEntityFactory.apply(try await KaiXAPIClient.shared.setBookmark(post.remoteId ?? post.id, isBookmarked), to: post)
            return
        }
        let bookmarkDelta = isBookmarked ? 1 : -1
        let previousHeat = countAlreadyUpdated
            ? heatScore(for: post, bookmarkDelta: bookmarkDelta)
            : post.heatScore
        if !countAlreadyUpdated, post.isBookmarkedByCurrentUser != isBookmarked {
            post.bookmarkCount = max(0, post.bookmarkCount + bookmarkDelta)
        }
        post.isBookmarkedByCurrentUser = isBookmarked
        try refreshHeatAndTopics(for: post, previousHeat: previousHeat)

        if isBookmarked && post.authorId != currentUserId && NotificationPreferenceService.isEnabled(.bookmark, recipientUserId: post.authorId) {
            try upsertNotification(type: .bookmark, actorId: currentUserId, targetPostId: post.id, content: "收藏了你的帖子")
        }

        try context.save()
    }

    func repost(post: PostEntity, currentUserId: String) async throws -> PostEntity {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            ServerEntityFactory.apply(try await KaiXAPIClient.shared.setRepost(post.remoteId ?? post.id, true), to: post)
            return post
        }
        let existing = try existingReposts(for: post, currentUserId: currentUserId)
        if let repost = existing.first {
            if existing.count > 1 {
                for duplicate in existing.dropFirst() {
                    context.delete(duplicate)
                }
                post.repostCount = max(1, post.repostCount - (existing.count - 1))
                try context.save()
            }
            post.isRepostedByCurrentUser = true
            return repost
        }

        if let repost = try await setRepost(post: post, isReposted: true, currentUserId: currentUserId) {
            return repost
        }

        guard let repost = try existingReposts(for: post, currentUserId: currentUserId).first else {
            throw RepositoryError.notFound
        }
        return repost
    }

    func quoteRepost(
        post: PostEntity,
        currentUserId: String,
        content: String,
        countAlreadyUpdated: Bool = false
    ) async throws -> PostEntity {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.validationFailed }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let quote = try await KaiXAPIClient.shared.quoteRepost(post.remoteId ?? post.id, content: trimmed)
            return ServerEntityFactory.post(from: quote)
        }

        let previousHeat = countAlreadyUpdated
            ? heatScore(for: post, repostDelta: 1)
            : post.heatScore
        let quote = PostEntity(
            authorId: currentUserId,
            content: trimmed,
            viewCount: 0,
            status: .published,
            hashtags: trimmed.extractedHashtags,
            repostOfPostId: post.id
        )
        context.insert(quote)
        if !countAlreadyUpdated {
            post.repostCount = max(0, post.repostCount + 1)
        }
        try refreshHeatAndTopics(for: post, previousHeat: previousHeat)

        if post.authorId != currentUserId && NotificationPreferenceService.isEnabled(.repost, recipientUserId: post.authorId) {
            try upsertNotification(type: .repost, actorId: currentUserId, targetPostId: post.id, content: trimmed)
        }

        try context.save()
        return quote
    }

    func setRepost(
        post: PostEntity,
        isReposted: Bool,
        currentUserId: String,
        countAlreadyUpdated: Bool = false
    ) async throws -> PostEntity? {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            ServerEntityFactory.apply(try await KaiXAPIClient.shared.setRepost(post.remoteId ?? post.id, isReposted), to: post)
            return nil
        }
        let existing = try existingReposts(for: post, currentUserId: currentUserId)
        let wasReposted = post.isRepostedByCurrentUser || !existing.isEmpty
        let repostDelta = isReposted ? 1 : -1
        let previousHeat = countAlreadyUpdated
            ? heatScore(for: post, repostDelta: repostDelta)
            : post.heatScore
        var resolvedRepost: PostEntity?

        if !countAlreadyUpdated, wasReposted != isReposted {
            post.repostCount = max(0, post.repostCount + repostDelta)
        }
        post.isRepostedByCurrentUser = isReposted

        if isReposted {
            if existing.isEmpty {
                let repost = PostEntity(
                    authorId: currentUserId,
                    content: "",
                    viewCount: 0,
                    status: .published,
                    hashtags: [],
                    repostOfPostId: post.id
                )
                context.insert(repost)
                resolvedRepost = repost
            } else {
                resolvedRepost = existing.first
                if countAlreadyUpdated {
                    post.repostCount = max(1, post.repostCount - 1)
                }
                if existing.count > 1 {
                    for duplicate in existing.dropFirst() {
                        context.delete(duplicate)
                    }
                    post.repostCount = max(1, post.repostCount - (existing.count - 1))
                }
            }

            if post.authorId != currentUserId && NotificationPreferenceService.isEnabled(.repost, recipientUserId: post.authorId) {
                try upsertNotification(type: .repost, actorId: currentUserId, targetPostId: post.id, content: "转发了你的帖子")
            }
        } else {
            for repost in existing {
                context.delete(repost)
            }
        }

        try refreshHeatAndTopics(for: post, previousHeat: previousHeat)
        try context.save()
        return resolvedRepost
    }

    func undoRepost(post: PostEntity, currentUserId: String) async throws {
        _ = try await setRepost(post: post, isReposted: false, currentUserId: currentUserId)
    }

    func addComment(
        post: PostEntity,
        authorId: String,
        content: String,
        parentCommentId: String? = nil,
        commentCountAlreadyUpdated: Bool = false
    ) async throws -> CommentEntity {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw RepositoryError.validationFailed }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let dto = try await KaiXAPIClient.shared.createComment(
                postId: post.remoteId ?? post.id,
                content: trimmed,
                parentId: parentCommentId
            )
            if !commentCountAlreadyUpdated {
                post.commentCount += 1
            }
            return ServerEntityFactory.comment(from: dto)
        }

        let previousHeat = commentCountAlreadyUpdated
            ? heatScore(for: post, commentDelta: 1)
            : post.heatScore
        let comment = CommentEntity(postId: post.id, authorId: authorId, content: trimmed, parentCommentId: parentCommentId)
        context.insert(comment)
        if !commentCountAlreadyUpdated {
            post.commentCount += 1
        }
        try refreshHeatAndTopics(for: post, previousHeat: previousHeat)

        if let parentCommentId,
           let parent = try fetchComment(id: parentCommentId),
           parent.authorId != authorId,
           NotificationPreferenceService.isEnabled(.reply, recipientUserId: parent.authorId) {
            try upsertNotification(
                type: .reply,
                actorId: authorId,
                targetPostId: post.id,
                targetCommentId: comment.id,
                content: trimmed
            )
        } else if post.authorId != authorId && NotificationPreferenceService.isEnabled(.comment, recipientUserId: post.authorId) {
            try upsertNotification(
                type: .comment,
                actorId: authorId,
                targetPostId: post.id,
                targetCommentId: comment.id,
                content: trimmed
            )
        }

        try context.save()
        return comment
    }

    func deleteComment(comment: CommentEntity, commentCountAlreadyUpdated: Bool = false) async throws {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            try await KaiXAPIClient.shared.deleteComment(comment.id)
            return
        }
        let postId = comment.postId
        let parentId = comment.id
        let descendants = try context.fetch(FetchDescriptor<CommentEntity>(
            predicate: #Predicate { $0.parentCommentId == parentId }
        ))
        let deleteCount = 1 + descendants.count
        if let post = try await fetchPost(id: postId) {
            if commentCountAlreadyUpdated {
                let previousHeat = heatScore(for: post, commentDelta: -deleteCount)
                try applyTopicHeatDelta(for: post, previousHeat: previousHeat)
            } else {
                let previousHeat = post.heatScore
                post.commentCount = max(0, post.commentCount - deleteCount)
                try refreshHeatAndTopics(for: post, previousHeat: previousHeat)
            }
        }
        descendants.forEach(context.delete)
        context.delete(comment)
        try context.save()
    }

    func deletePost(post: PostEntity) async throws {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            try await KaiXAPIClient.shared.deletePost(post.remoteId ?? post.id)
            return
        }
        let postId = post.id
        let reposts = try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.repostOfPostId == postId }
        ))
        let affectedPostIds = [postId] + reposts.map(\.id)
        let comments = try context.fetch(FetchDescriptor<CommentEntity>(
            predicate: #Predicate { affectedPostIds.contains($0.postId) }
        ))
        let media = try context.fetch(FetchDescriptor<MediaEntity>(
            predicate: #Predicate { affectedPostIds.contains($0.postId) }
        ))
        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>()).filter { notification in
            notification.targetPostId.map { affectedPostIds.contains($0) } ?? false
        }

        comments.forEach(context.delete)
        media.forEach(context.delete)
        notifications.forEach(context.delete)
        reposts.forEach(context.delete)
        context.delete(post)
        try rebuildTopics()
        try context.save()
    }

    func updatePost(post: PostEntity, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw RepositoryError.validationFailed }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            ServerEntityFactory.apply(try await KaiXAPIClient.shared.editPost(post.remoteId ?? post.id, content: trimmed), to: post)
            return
        }

        post.content = trimmed
        post.hashtags = trimmed.extractedHashtags
        post.updatedAt = .now
        heatService.refresh(post)
        try rebuildTopics()
        try context.save()
    }

    private func followingIds(for userId: String) throws -> Set<String> {
        let follows = try context.fetch(FetchDescriptor<FollowEntity>(
            predicate: #Predicate { $0.followerId == userId }
        ))
        return Set(follows.map(\.followingId))
    }

    private func existingReposts(for post: PostEntity, currentUserId: String) throws -> [PostEntity] {
        let postId = post.id
        let reposts = try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.authorId == currentUserId && $0.repostOfPostId == postId },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        return reposts.filter { repost in
            let trimmed = repost.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == post.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func refreshRepostState(for posts: [PostEntity], currentUserId: String) throws {
        guard !posts.isEmpty else { return }
        let authoredPosts = try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.authorId == currentUserId && $0.repostOfPostId != nil }
        ))
        let repostedIds = Set(authoredPosts.compactMap(\.repostOfPostId))
        for post in posts {
            post.isRepostedByCurrentUser = repostedIds.contains(post.id)
        }
    }

    private func fetchComment(id: String) throws -> CommentEntity? {
        var descriptor = FetchDescriptor<CommentEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func upsertNotification(
        type: NotificationType,
        actorId: String,
        targetPostId: String?,
        targetCommentId: String? = nil,
        content: String
    ) throws {
        let typeRaw = type.rawValue
        let matches = try context.fetch(FetchDescriptor<NotificationEntity>(
            predicate: #Predicate {
                $0.typeRaw == typeRaw
                && $0.actorId == actorId
                && $0.targetPostId == targetPostId
                && $0.targetCommentId == targetCommentId
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))

        if let first = matches.first {
            first.content = content
            first.targetCommentId = targetCommentId
            first.createdAt = .now
            first.isRead = false
            for duplicate in matches.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            context.insert(NotificationEntity(
                type: type,
                actorId: actorId,
                targetPostId: targetPostId,
                targetCommentId: targetCommentId,
                content: content
            ))
        }
    }

    private func refreshHeatAndTopics(for post: PostEntity, previousHeat: Double) throws {
        heatService.refresh(post)
        try applyTopicHeatDelta(for: post, previousHeat: previousHeat)
    }

    private func applyTopicHeatDelta(for post: PostEntity, previousHeat: Double) throws {
        let delta = post.heatScore - previousHeat
        guard abs(delta) > 0.0001 else { return }

        for name in post.hashtags.map(\.normalizedTopicName) where !name.isEmpty {
            var descriptor = FetchDescriptor<TopicEntity>(predicate: #Predicate { $0.name == name })
            descriptor.fetchLimit = 1
            if let topic = try context.fetch(descriptor).first {
                topic.heatScore = max(0, topic.heatScore + delta)
                topic.updatedAt = .now
            } else {
                context.insert(TopicEntity(name: name, postCount: 1, heatScore: max(0, post.heatScore)))
            }
        }
    }

    private func heatScore(
        for post: PostEntity,
        viewDelta: Int = 0,
        likeDelta: Int = 0,
        commentDelta: Int = 0,
        repostDelta: Int = 0,
        bookmarkDelta: Int = 0
    ) -> Double {
        heatService.calculate(
            viewCount: max(0, post.viewCount - viewDelta),
            likeCount: max(0, post.likeCount - likeDelta),
            commentCount: max(0, post.commentCount - commentDelta),
            repostCount: max(0, post.repostCount - repostDelta),
            bookmarkCount: max(0, post.bookmarkCount - bookmarkDelta),
            reportCount: post.reportCount,
            boostWeight: post.boostWeight,
            boostedUntil: post.boostedUntil,
            createdAt: post.createdAt
        )
    }

    private func rebuildTopics() throws {
        let topics = try context.fetch(FetchDescriptor<TopicEntity>())
        topics.forEach(context.delete)

        let published = PostStatus.published.rawValue
        let active = PostStatus.active.rawValue
        let posts = try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.statusRaw == published || $0.statusRaw == active }
        ))
        let grouped = Dictionary(grouping: posts.flatMap { post in
            post.hashtags.map { ($0.normalizedTopicName, post.heatScore) }
        }, by: { $0.0 })

        for (name, values) in grouped where !name.isEmpty {
            context.insert(TopicEntity(
                name: name,
                postCount: values.count,
                heatScore: values.reduce(0) { $0 + $1.1 }
            ))
        }
    }
}
