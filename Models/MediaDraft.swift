import Foundation

struct MediaDraft: Identifiable, Equatable {
    let id: String
    let type: MediaType
    let localURL: URL
    let thumbnailURL: URL
    let width: Double
    let height: Double
    let duration: Double
}
