import Foundation

struct HeatScoreService {
    static let shared = HeatScoreService()

    func calculate(
        viewCount: Int,
        likeCount: Int,
        commentCount: Int,
        repostCount: Int,
        bookmarkCount: Int,
        reportCount: Int = 0,
        boostWeight: Double = 0,
        boostedUntil: Date? = nil,
        createdAt: Date,
        referenceDate: Date = .now
    ) -> Double {
        let ageHours = max(0, referenceDate.timeIntervalSince(createdAt) / 3600)
        let timeDecay = max(0, 24 - ageHours)
        let activeBoost = boostedUntil.map { $0 > referenceDate } == true ? boostWeight : 0
        let base = Double(likeCount)
            + Double(commentCount * 3)
            + Double(repostCount * 5)
            + Double(bookmarkCount * 4)
            - Double(reportCount * 10)
            + activeBoost
            + timeDecay
        return max(0, base)
    }

    func refresh(_ post: PostEntity) {
        post.heatScore = calculate(
            viewCount: post.viewCount,
            likeCount: post.likeCount,
            commentCount: post.commentCount,
            repostCount: post.repostCount,
            bookmarkCount: post.bookmarkCount,
            reportCount: post.reportCount,
            boostWeight: post.boostWeight,
            boostedUntil: post.boostedUntil,
            createdAt: post.createdAt
        )
        post.updatedAt = .now
    }
}
