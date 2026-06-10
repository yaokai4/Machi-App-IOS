import SwiftUI

enum KaiXTheme {
    static let pageBackground = KXColor.pageBackground
    static let cardBackground = KXColor.elevatedBackground
    static let softBackground = KXColor.softBackground
    static let line = KXColor.separator
    static let glassStroke = KXColor.glassStroke
    static let mutedGlassStroke = KXColor.separator
    static let accent = KXColor.accent
    static let heat = KXColor.heat
    static let horizontalPadding: CGFloat = KXSpacing.screen
    static let cardRadius: CGFloat = KXRadius.card
    static let compactRadius: CGFloat = KXRadius.sm
    static let bottomBarHeight: CGFloat = 66
    /// Bottom inset reserved for floating TabBar + safe-area on
    /// every scrollable surface. This keeps the last card tappable
    /// while the glass tab bar floats over the feed content.
    static let bottomContentPadding: CGFloat = 98
}

enum KaiXConfig {
    static let schemaVersion = 6
    static let seedVersion = 7
    static let pageSize = 15
    static let maxImageItemsPerPost = 9
    static let maxVideoItemsPerPost = 1
    static let maxMediaItemsPerPost = maxImageItemsPerPost
    static let maxPostImageBytes = 10 * 1024 * 1024
    static let maxPostVideoBytes = 200 * 1024 * 1024
    static let maxMessageImageBytes = 10 * 1024 * 1024
    static let maxMessageVideoBytes = 100 * 1024 * 1024
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

extension View {
    func kaixGlassCard(cornerRadius: CGFloat = KaiXTheme.cardRadius) -> some View {
        self
            .kxGlassSurface(radius: cornerRadius)
    }
}
