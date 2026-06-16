import Foundation

struct MediaDraft: Identifiable, Equatable, Sendable {
    let id: String
    let type: MediaType
    let localURL: URL
    let thumbnailURL: URL
    let contentType: String
    let fileName: String
    let width: Double
    let height: Double
    let duration: Double
    let originalFileSize: Int
    let uploadFileSize: Int

    nonisolated init(
        id: String,
        type: MediaType,
        localURL: URL,
        thumbnailURL: URL,
        contentType: String,
        fileName: String,
        width: Double,
        height: Double,
        duration: Double,
        originalFileSize: Int = 0,
        uploadFileSize: Int = 0
    ) {
        self.id = id
        self.type = type
        self.localURL = localURL
        self.thumbnailURL = thumbnailURL
        self.contentType = contentType
        self.fileName = fileName
        self.width = width
        self.height = height
        self.duration = duration
        self.originalFileSize = originalFileSize
        self.uploadFileSize = uploadFileSize
    }

    var aspectRatio: Double {
        guard width > 0, height > 0 else { return 1 }
        return width / height
    }
}
