import Foundation

enum KaiXRuntimeFlags {
    static var allowLocalStoreFallback: Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        return env["KAIX_UI_TEST_LOCAL_AUTH"] == "1"
            || env["KAIX_ALLOW_LOCAL_STORE"] == "1"
            || args.contains("-kaixUITestLocalAuth")
        #else
        return false
        #endif
    }
}

@MainActor
enum ServerEntityFactory {
    struct PostBundle {
        let orderedPosts: [PostEntity]
        let allPosts: [PostEntity]
        let authors: [String: UserEntity]
        let mediaByPostId: [String: [MediaEntity]]
    }

    static func postBundle(from dtos: [KaiXPostDTO]) -> PostBundle {
        var orderedPosts: [PostEntity] = []
        var allPosts: [PostEntity] = []
        var authors: [String: UserEntity] = [:]
        var mediaByPostId: [String: [MediaEntity]] = [:]
        var seenPosts = Set<String>()

        for dto in dtos {
            if let author = dto.author {
                authors[author.id] = UserRepository.entity(from: author)
            }
            let primaryPost = post(from: dto)
            orderedPosts.append(primaryPost)
            if seenPosts.insert(primaryPost.id).inserted {
                allPosts.append(primaryPost)
            }
            mediaByPostId[primaryPost.id] = media(from: dto.media, postId: primaryPost.id)

            if let original = dto.original_post {
                if let author = original.author {
                    authors[author.id] = UserRepository.entity(from: author)
                }
                let originalPost = post(from: original)
                if seenPosts.insert(originalPost.id).inserted {
                    allPosts.append(originalPost)
                }
                mediaByPostId[originalPost.id] = media(from: original.media, postId: originalPost.id)
            }
        }

        return PostBundle(
            orderedPosts: orderedPosts,
            allPosts: allPosts,
            authors: authors,
            mediaByPostId: mediaByPostId
        )
    }

    static func post(from dto: KaiXPostDTO) -> PostEntity {
        PostEntity(
            id: dto.id,
            authorId: dto.author_id,
            content: dto.content,
            createdAt: date(dto.createdAt ?? dto.created_at),
            updatedAt: date(dto.updatedAt ?? dto.updated_at),
            commentCount: dto.commentCount ?? dto.comment_count,
            repostCount: dto.repostCount ?? dto.repost_count,
            likeCount: dto.likeCount ?? dto.like_count,
            bookmarkCount: dto.bookmarkCount ?? dto.bookmark_count,
            viewCount: dto.viewCount ?? dto.view_count,
            heatScore: dto.heatScore ?? dto.heat_score,
            isLikedByCurrentUser: dto.isLiked ?? dto.liked,
            isBookmarkedByCurrentUser: dto.isSaved ?? dto.saved ?? dto.bookmarked,
            isRepostedByCurrentUser: dto.isReposted ?? dto.reposted,
            status: dto.status.flatMap(PostStatus.init(rawValue:)) ?? .published,
            hashtags: dto.tags,
            repostOfPostId: dto.repost_of_id,
            remoteId: dto.remote_id ?? dto.id,
            syncStatus: .synced,
            country: dto.country ?? "",
            province: dto.province ?? "",
            city: dto.city ?? "",
            regionCode: dto.region_code ?? dto.city_path ?? dto.cityPath ?? "",
            contentType: (dto.content_type ?? dto.contentType ?? dto.category).flatMap(ContentType.init(rawValue:)) ?? .dynamic,
            attributesRaw: dto.attributes.map(encodeAttributes) ?? "",
            reportCount: dto.report_count ?? 0,
            isBoosted: dto.is_boosted ?? false,
            boostWeight: dto.boost_weight ?? 0,
            boostedUntil: parseDate(dto.boosted_until),
            language: dto.language ?? "",
            isSeedContent: dto.is_seed_content ?? false,
            seedAuthorType: dto.seed_author_type ?? ""
        )
    }

    static func post(from dto: KaiXPostDTO.OptionalPost) -> PostEntity {
        PostEntity(
            id: dto.id,
            authorId: dto.author_id,
            content: dto.content,
            createdAt: date(dto.created_at),
            updatedAt: date(dto.updated_at),
            commentCount: dto.comment_count,
            repostCount: dto.repost_count,
            likeCount: dto.like_count,
            bookmarkCount: dto.bookmark_count,
            viewCount: dto.view_count,
            heatScore: dto.heat_score,
            isLikedByCurrentUser: dto.liked,
            isBookmarkedByCurrentUser: dto.bookmarked,
            isRepostedByCurrentUser: dto.reposted,
            status: .published,
            hashtags: dto.tags,
            remoteId: dto.id,
            syncStatus: .synced
        )
    }

    static func media(from dtos: [KaiXMediaDTO], postId: String) -> [MediaEntity] {
        dtos.map { media(from: $0, postId: postId) }
    }

    static func media(from dto: KaiXMediaDTO, postId: String) -> MediaEntity {
        let mediaType: MediaType = dto.normalizedType == "video" ? .video : .image
        let preview = mediaType == .video ? dto.posterURLString : dto.thumbnailURLString
        let medium = mediaType == .video ? dto.sourceURLString : dto.mediumURLString
        let remoteId = dto.remote_id ?? dto.remoteId ?? dto.id
        return MediaEntity(
            id: dto.id,
            postId: postId,
            type: mediaType,
            remoteURL: medium,
            mediumURL: medium,
            originalURL: dto.sourceURLString,
            thumbnailURL: preview,
            width: Double(dto.width ?? 0),
            height: Double(dto.height ?? 0),
            duration: dto.durationSeconds ?? dto.duration_seconds ?? dto.duration ?? 0,
            fileSize: dto.fileSize ?? dto.file_size ?? dto.byte_size ?? 0,
            mimeType: dto.contentType ?? dto.content_type ?? dto.mime ?? "",
            uploadState: .uploaded,
            uploadProgress: 1,
            createdAt: parseDate(dto.createdAt ?? dto.created_at) ?? .now,
            updatedAt: .now,
            remoteId: remoteId,
            syncStatus: .synced
        )
    }

    static func comment(from dto: KaiXCommentDTO) -> CommentEntity {
        CommentEntity(
            id: dto.id,
            postId: dto.post_id,
            authorId: dto.author_id,
            content: dto.content,
            parentCommentId: dto.parent_comment_id,
            likeCount: dto.like_count,
            isLikedByCurrentUser: dto.liked,
            createdAt: date(dto.created_at),
            updatedAt: date(dto.updated_at),
            remoteId: dto.id,
            syncStatus: .synced
        )
    }

    static func topic(from dto: KaiXTopicDTO) -> TopicEntity {
        TopicEntity(
            id: "topic-\(dto.normalizedTag)",
            name: dto.normalizedTag,
            postCount: dto.postCountValue,
            heatScore: dto.heatScoreValue
        )
    }

    static func apply(_ dto: KaiXPostDTO, to post: PostEntity) {
        let updated = self.post(from: dto)
        post.authorId = updated.authorId
        post.content = updated.content
        post.commentCount = updated.commentCount
        post.repostCount = updated.repostCount
        post.likeCount = updated.likeCount
        post.bookmarkCount = updated.bookmarkCount
        post.viewCount = updated.viewCount
        post.heatScore = updated.heatScore
        post.isLikedByCurrentUser = updated.isLikedByCurrentUser
        post.isBookmarkedByCurrentUser = updated.isBookmarkedByCurrentUser
        post.isRepostedByCurrentUser = updated.isRepostedByCurrentUser
        post.statusRaw = updated.statusRaw
        post.hashtagsRaw = updated.hashtagsRaw
        post.repostOfPostId = updated.repostOfPostId
        post.remoteId = updated.remoteId
        post.syncStatus = .synced
        post.country = updated.country
        post.province = updated.province
        post.city = updated.city
        post.regionCode = updated.regionCode
        post.contentTypeRaw = updated.contentTypeRaw
        post.attributesRaw = updated.attributesRaw
        post.reportCount = updated.reportCount
        post.isBoosted = updated.isBoosted
        post.boostWeight = updated.boostWeight
        post.boostedUntil = updated.boostedUntil
        post.language = updated.language
        post.isSeedContent = updated.isSeedContent
        post.seedAuthorType = updated.seedAuthorType
        post.updatedAt = .now
    }

    static func encodeAttributes(_ map: [String: KaiXAttributeValue]) -> String {
        var plain: [String: Any] = [:]
        for (key, value) in map {
            switch value.kind {
            case .string(let string):
                plain[key] = string
            case .double(let number):
                plain[key] = number
            case .bool(let bool):
                plain[key] = bool
            case .json(let json):
                plain[key] = json.foundationObject
            case .null:
                continue
            }
        }
        guard !plain.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: plain, options: [.sortedKeys]) else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func date(_ raw: String?) -> Date {
        parseDate(raw) ?? .now
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: raw)
    }
}
