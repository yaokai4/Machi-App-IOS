import Foundation

enum RepositoryError: LocalizedError {
    case validationFailed
    case notFound
    case duplicate
    case saveFailed
    case mediaFailed
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .validationFailed: "The input is invalid."
        case .notFound: "The requested record was not found."
        case .duplicate: "The record already exists."
        case .saveFailed: "Could not save changes."
        case .mediaFailed: "Could not process media."
        case .authenticationRequired: "Please log in to continue."
        }
    }
}

enum AppError: Equatable, LocalizedError {
    case validation
    case notFound
    case duplicate
    case persistence
    case media
    case network
    case permission
    case unknown

    init(_ error: Error) {
        if let appError = error as? AppError {
            self = appError
            return
        }

        if let repositoryError = error as? RepositoryError {
            switch repositoryError {
            case .validationFailed:
                self = .validation
            case .notFound:
                self = .notFound
            case .duplicate:
                self = .duplicate
            case .saveFailed:
                self = .persistence
            case .mediaFailed:
                self = .media
            case .authenticationRequired:
                self = .permission
            }
            return
        }

        self = .unknown
    }

    var errorDescription: String? {
        userMessage
    }

    var userMessage: String {
        switch self {
        case .validation:
            "内容不完整，请检查后重试。"
        case .notFound:
            "内容不存在或已被删除。"
        case .duplicate:
            "内容已存在，请勿重复提交。"
        case .persistence:
            "保存失败，请稍后重试。"
        case .media:
            "媒体处理失败，请换一个文件重试。"
        case .network:
            "网络连接不可用，请稍后重试。"
        case .permission:
            "权限不足，请检查系统设置。"
        case .unknown:
            "操作失败，请稍后重试。"
        }
    }
}

extension Error {
    var kaixUserMessage: String {
        AppError(self).userMessage
    }
}
