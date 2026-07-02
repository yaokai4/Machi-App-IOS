import Foundation
import SwiftUI

enum ErrorState {
    case offline
    case databaseRecovered(message: String, technicalDetails: String?)
    case databaseRecoveryMode(message: String, technicalDetails: String?)
    case syncDelayed
    case requestFailed(message: String, technicalDetails: String?)
    case custom(title: String, message: String, systemImage: String, tint: Color, technicalDetails: String?)
    /// Post-publish success banner. `actionTitle` labels the tap-through button
    /// (e.g. "查看") whose closure is supplied via `ToastManager.show(retry:)`.
    case publishedSuccess(title: String, actionTitle: String)

    var title: String {
        switch self {
        case .offline:
            "当前离线"
        case .databaseRecovered:
            "数据库已修复"
        case .databaseRecoveryMode:
            #if DEBUG
            "数据库恢复模式"
            #else
            "本地数据恢复中"
            #endif
        case .syncDelayed:
            "同步稍后继续"
        case .requestFailed:
            "操作未完成"
        case .custom(let title, _, _, _, _):
            title
        case .publishedSuccess(let title, _):
            title
        }
    }

    var message: String {
        switch self {
        case .offline:
            "网络恢复后会自动刷新内容。"
        case .databaseRecovered(let message, _):
            message
        case .databaseRecoveryMode(let message, _):
            message
        case .syncDelayed:
            "当前内容已保存在本机，稍后会继续同步。"
        case .requestFailed(let message, _):
            message
        case .custom(_, let message, _, _, _):
            message
        case .publishedSuccess:
            ""
        }
    }

    var systemImage: String {
        switch self {
        case .offline:
            "wifi.slash"
        case .databaseRecovered:
            "checkmark.seal"
        case .databaseRecoveryMode:
            "externaldrive"
        case .syncDelayed:
            "arrow.triangle.2.circlepath"
        case .requestFailed:
            "xmark.octagon"
        case .custom(_, _, let systemImage, _, _):
            systemImage
        case .publishedSuccess:
            "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .offline:
            .orange
        case .databaseRecovered:
            .green
        case .databaseRecoveryMode:
            .orange
        case .syncDelayed:
            .blue
        case .requestFailed:
            .red
        case .custom(_, _, _, let tint, _):
            tint
        case .publishedSuccess:
            .green
        }
    }

    var retryTitle: String? {
        switch self {
        case .offline:
            nil
        case .databaseRecovered, .databaseRecoveryMode, .requestFailed:
            "重试"
        case .syncDelayed:
            nil
        case .custom:
            "重试"
        case .publishedSuccess(_, let actionTitle):
            actionTitle
        }
    }

    var technicalDetails: String? {
        switch self {
        case .offline, .syncDelayed, .publishedSuccess:
            nil
        case .databaseRecovered(_, let details),
             .databaseRecoveryMode(_, let details),
             .requestFailed(_, let details),
             .custom(_, _, _, _, let details):
            details
        }
    }
}

extension ErrorState {
    static func database(_ notice: DatabaseRecoveryNotice) -> ErrorState {
        switch notice.mode {
        case .primary:
            .syncDelayed
        case .rebuiltPrimary:
            .databaseRecovered(message: notice.userMessage, technicalDetails: notice.technicalDetails)
        case .recovery, .ephemeral:
            .databaseRecoveryMode(message: notice.userMessage, technicalDetails: notice.technicalDetails)
        }
    }
}
