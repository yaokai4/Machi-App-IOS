import Foundation

/// Single source of truth for "how the feed is ranked once SwiftData
/// has handed us a page." SwiftData's `#Predicate` can't easily take
/// a string array (the runtime checker rejects most generic
/// expressions), so we keep the DB predicate narrow (status / region /
/// type) and apply the language + boost weighting in memory here.
///
/// The score is:
/// ```
/// score = heatScore
///       + 500  if regionCode matches the user's current region
///       + 200  if only the country matches
///       + 300  if the post.language matches preferred
///       + 120  if it matches a fallback language
///       + boostBonus
/// ```
/// Then it falls back to `createdAt` desc for ties. Numbers are
/// intentionally large compared to typical heat so a language miss
/// can't easily outrank a language hit.
enum FeedQueryBuilder {
    struct RankingContext {
        let region: KaiXRegionDirectory.Region?
        let preferredLanguage: ContentLanguage?
        let fallbackLanguages: [ContentLanguage]
        /// When true, posts whose `language` does not match preferred
        /// *or* fallback are dropped (instead of being demoted). Used
        /// when the user explicitly picked a single language and we
        /// have enough content to honor it strictly.
        let strictLanguageFilter: Bool
    }

    /// Compose a ranking context from the live region + language
    /// stores. App callers should use this so the policy stays in one
    /// place; tests can build a context manually.
    @MainActor
    static func context(for appLanguage: AppLanguage, strict: Bool = false) -> RankingContext {
        let manager = LanguageManager.shared
        let primary = manager.resolvedPrimary(for: appLanguage)
        let fallbacks = manager.fallbacks.filter { $0 != primary }
        return RankingContext(
            region: RegionStore.shared.current,
            preferredLanguage: primary,
            fallbackLanguages: fallbacks,
            strictLanguageFilter: strict
        )
    }

    /// Apply ranking + (optional) hard filter to a fetched page.
    ///
    /// **In-memory only.** Don't call this on large arrays; feed paging
    /// already caps each call to ~15-30 rows.
    static func rank(_ posts: [PostEntity], using ctx: RankingContext) -> [PostEntity] {
        // Fast path — when no region is set and no language preference
        // is meaningful, the score is just `heatScore + boost`, and the
        // SwiftData fetch already sorted by heat/createdAt. Skip the
        // sort entirely so list scroll stays smooth.
        let primaryTag = ctx.preferredLanguage?.serverTag ?? ""
        let fallbackTags = Set(ctx.fallbackLanguages.map(\.serverTag).filter { !$0.isEmpty })
        if ctx.region == nil && primaryTag.isEmpty && fallbackTags.isEmpty {
            return posts
        }

        let filtered: [PostEntity]
        if ctx.strictLanguageFilter,
           !primaryTag.isEmpty,
           // Only strict-filter if we have enough hits to fill at least
           // half a typical page. Below that, fall through to ranking
           // mode so users still see something.
           posts.filter({ $0.language == primaryTag }).count >= 6 {
            filtered = posts.filter { post in
                post.language == primaryTag || fallbackTags.contains(post.language)
            }
        } else {
            filtered = posts
        }

        // Pre-compute scores once instead of computing twice per
        // comparison — Swift's `.sorted(by:)` calls the closure O(n log n)
        // times so even modest score work is wasted CPU on the main
        // thread.
        let scored = filtered.map { post -> (PostEntity, Double) in
            (post, score(post, ctx: ctx, primary: primaryTag, fallbacks: fallbackTags))
        }
        return scored.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.createdAt > rhs.0.createdAt }
            return lhs.1 > rhs.1
        }.map(\.0)
    }

    private static func score(
        _ post: PostEntity,
        ctx: RankingContext,
        primary: String,
        fallbacks: Set<String>
    ) -> Double {
        var s = post.heatScore
        if let region = ctx.region {
            if post.regionCode == region.regionCode {
                s += 500
            } else if post.country == region.countryCode {
                s += 200
            }
        }
        if !primary.isEmpty {
            if post.language == primary {
                s += 300
            } else if fallbacks.contains(post.language) {
                s += 120
            }
        }
        if post.isBoosted {
            if let until = post.boostedUntil, until > .now {
                s += max(0, post.boostWeight) * 1000
            } else if post.boostedUntil == nil {
                s += max(0, post.boostWeight) * 1000
            }
        }
        return s
    }
}
