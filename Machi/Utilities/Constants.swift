import SwiftUI

// KaiXTheme 兼容别名层已完成历史使命：全部调用点已迁移至 KX* token
// （颜色/间距/圆角见 DesignSystem.swift；悬浮 TabBar 布局常量收入 KXLayout），
// 别名层于批次2清除。新代码一律直接使用 KX* 命名空间。

enum KaiXConfig {
    static let schemaVersion = 7
    static let seedVersion = 7
    static let pageSize = 15
    static let maxImageItemsPerPost = 9
    static let maxVideoItemsPerPost = 1
    static let maxMediaItemsPerPost = maxImageItemsPerPost
    static let maxPostImageBytes = 10 * 1024 * 1024
    static let maxPostVideoBytes = 200 * 1024 * 1024
    /// Selection-time guard before compression/transcoding. The upload guard
    /// remains `maxPostImageBytes` / `maxPostVideoBytes`; these larger caps
    /// avoid rejecting high-resolution camera originals before we can shrink
    /// them into the publishable format.
    static let maxPostImageSourceBytes = 80 * 1024 * 1024
    static let maxPostVideoSourceBytes = 1024 * 1024 * 1024
    static let maxMessageImageBytes = 10 * 1024 * 1024
    static let maxMessageVideoBytes = 200 * 1024 * 1024
    static let maxMessageVideoDuration: TimeInterval = 2 * 60
    /// Hard cap on a single post's character count. Mirrors the
    /// server-side cap in `web/server.py:api_create_post` so the two
    /// clients reject the same payloads. Bumping this value here
    /// without also bumping it on the server will let users compose
    /// posts that the backend then refuses.
    static let maxPostCharacters = 2000
}

enum KaiXBuild {
    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

}

