import Foundation
import SwiftData

@Model
final class MediaEntity {
    @Attribute(.unique) var id: String
    var postId: String
    var typeRaw: String
    var localURL: String
    var remoteURL: String
    var thumbnailURL: String
    var width: Double
    var height: Double
    var duration: Double
    var uploadStateRaw: String
    var uploadProgress: Double
    var createdAt: Date
    var placeholderSymbol: String = ""
    var placeholderTitle: String = ""
    var placeholderColorName: String = ""
    var updatedAt: Date
    var remoteId: String?
    var syncStatusRaw: String
    var deletedAt: Date?
    var cursor: String?

    init(
        id: String = UUID().uuidString,
        postId: String,
        type: MediaType,
        localURL: String = "",
        remoteURL: String = "",
        thumbnailURL: String = "",
        width: Double = 0,
        height: Double = 0,
        duration: Double = 0,
        uploadState: UploadState = .local,
        uploadProgress: Double = 0,
        createdAt: Date = .now,
        placeholderSymbol: String = "",
        placeholderTitle: String = "",
        placeholderColorName: String = "",
        updatedAt: Date = .now,
        remoteId: String? = nil,
        syncStatus: SyncStatus = .local,
        deletedAt: Date? = nil,
        cursor: String? = nil
    ) {
        self.id = id
        self.postId = postId
        self.typeRaw = type.rawValue
        self.localURL = localURL
        self.remoteURL = remoteURL
        self.thumbnailURL = thumbnailURL
        self.width = width
        self.height = height
        self.duration = duration
        self.uploadStateRaw = uploadState.rawValue
        self.uploadProgress = uploadProgress
        self.createdAt = createdAt
        self.placeholderSymbol = placeholderSymbol
        self.placeholderTitle = placeholderTitle
        self.placeholderColorName = placeholderColorName
        self.updatedAt = updatedAt
        self.remoteId = remoteId
        self.syncStatusRaw = syncStatus.rawValue
        self.deletedAt = deletedAt
        self.cursor = cursor
    }
}

extension MediaEntity {
    var type: MediaType {
        get { MediaType(rawValue: typeRaw) ?? .image }
        set { typeRaw = newValue.rawValue }
    }

    var uploadState: UploadState {
        get { UploadState(rawValue: uploadStateRaw) ?? .local }
        set { uploadStateRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .local }
        set {
            syncStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var displayURL: URL? {
        if !thumbnailURL.isEmpty { return thumbnailURL.asMediaURL }
        if !localURL.isEmpty { return localURL.asMediaURL }
        if !remoteURL.isEmpty { return URL(string: remoteURL) }
        return nil
    }
}

private extension String {
    var asMediaURL: URL? {
        if hasPrefix("/") {
            return URL(fileURLWithPath: self)
        }
        return URL(string: self) ?? URL(fileURLWithPath: self)
    }
}
