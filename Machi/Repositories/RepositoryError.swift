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
    /// A stale notification/deep link pointing at a removed resource is an
    /// expected empty state, not an operational failure. Detail screens use
    /// this to avoid presenting a red "Error" page for normal 404 lifecycle
    /// events such as a deleted post or a closed listing.
    var isKaiXResourceNotFound: Bool {
        guard let apiError = self as? KaiXAPIError else {
            if let repositoryError = self as? RepositoryError,
               case .notFound = repositoryError { return true }
            return false
        }
        return [
            "not_found", "http_404", "post_not_found", "post_deleted",
            "listing_not_found", "listing_deleted"
        ].contains(apiError.error.code)
    }

    /// User-facing message for an error. For server (`KaiXAPIError`) failures we
    /// first try to localize by the error *code* against the app's current
    /// language (high-frequency codes are hand-translated zh/ja/en), and only
    /// fall back to the raw server `message` when the code is unknown. The app
    /// language is resolved from `UserDefaults` (mirrors AppRouter) so this stays
    /// a plain, call-site-agnostic `Error` extension.
    var kaixUserMessage: String {
        let language = AppLanguage.resolved(
            from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? AppLanguage.system.rawValue
        )
        if let apiError = self as? KaiXAPIError {
            if let key = Self.localizationKey(forAPICode: apiError.error.code) {
                return L(key, language)
            }
            // Unknown code: prefer the server's own (already localized) message,
            // but never surface an empty string.
            let serverMessage = apiError.error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return serverMessage.isEmpty ? L("errGeneric", language) : serverMessage
        }
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return L("errNetwork", language)
            default:
                break
            }
        }
        return AppError(self).userMessage
    }

    /// Map a high-frequency server error `code` to a localization table key.
    /// Returns nil for codes we don't hand-translate (caller falls back to the
    /// server message). `http_401`/`http_403`/`http_404` variants are folded in
    /// alongside their semantic aliases.
    private static func localizationKey(forAPICode code: String) -> String? {
        switch code {
        case "rate_limited":
            return "errRateLimited"
        case "network_error", "timeout":
            return "errNetwork"
        case "not_found", "http_404":
            return "errNotFound"
        case "blocked", "user_blocked":
            return "errBlocked"
        case "forbidden", "http_403":
            return "errForbidden"
        case "MEMBERSHIP_REQUIRED", "membership_required":
            return "errMembershipRequired"
        case "MEMBERSHIP_LISTING_QUOTA_EXCEEDED", "listing_quota_exceeded":
            return "errListingQuotaExceeded"
        default:
            return nil
        }
    }
}
