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

    /// 内建 case 的文案曾是硬编码中文,断网/同步延迟时日英用户也只看到中文。
    /// ErrorState 是模型层拿不到 @Environment(\.appLanguage),按仓库既有模式
    /// (GuideOSViewModel / PostRepository)从 UserDefaults 解析当前语言,
    /// 展示时(计算属性)实时求值,切语言后新 toast 立即生效。
    private var language: AppLanguage {
        AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? "")
    }

    /// 内联三语(LocalizationService 缺这些键;禁止改动该文件,故就地内联)。
    private func t(_ zh: String, _ ja: String, _ en: String) -> String {
        switch language {
        case .ja: ja
        case .en: en
        default: zh
        }
    }

    var title: String {
        switch self {
        case .offline:
            t("当前离线", "現在オフラインです", "You're offline")
        case .databaseRecovered:
            t("数据库已修复", "データベースを修復しました", "Database repaired")
        case .databaseRecoveryMode:
            #if DEBUG
            t("数据库恢复模式", "データベース復旧モード", "Database recovery mode")
            #else
            t("本地数据恢复中", "ローカルデータを復旧中", "Recovering local data")
            #endif
        case .syncDelayed:
            t("同步稍后继续", "同期は後で再開します", "Sync will continue later")
        case .requestFailed:
            t("操作未完成", "操作は完了しませんでした", "Action didn't complete")
        case .custom(let title, _, _, _, _):
            title
        case .publishedSuccess(let title, _):
            title
        }
    }

    var message: String {
        switch self {
        case .offline:
            t("网络恢复后会自动刷新内容。",
              "接続が回復すると自動的に更新されます。",
              "Content refreshes automatically once you're back online.")
        case .databaseRecovered(let message, _):
            message
        case .databaseRecoveryMode(let message, _):
            message
        case .syncDelayed:
            t("当前内容已保存在本机，稍后会继续同步。",
              "内容はこの端末に保存済みです。後で自動的に同期されます。",
              "Saved on this device; it will sync again later.")
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
            L("retry", language)
        case .syncDelayed:
            nil
        case .custom:
            L("retry", language)
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
