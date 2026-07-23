import Foundation
import NaturalLanguage

/// Inline「翻译」support for post cards (feed + detail).
///
/// Responsibilities:
///  • Decide whether a post body deserves a translate entry point for the
///    current UI language. The server's `posts.language` tag is the
///    preferred signal; `NLLanguageRecognizer` is the fallback for legacy
///    posts that never got tagged.
///  • Cache finished translations in memory (per post × target language)
///    so toggling the translation or re-scrolling a card never re-runs
///    the ML model.
///
/// The actual translation runs through Apple's on-device Translation
/// framework (iOS 18+ `TranslationSession` via `.translationTask`) — see
/// `PostTranslationSection` in PostCardView.swift. Deliberately NOT
/// @MainActor: `.translationTask`'s action closure is a plain nonisolated
/// async closure, and a lock-guarded sync API lets both the View body and
/// that closure call in without `await` (no isolation hops, no
/// unnecessary-await warnings under Swift 6).
final class PostTranslationService: @unchecked Sendable {
    static let shared = PostTranslationService()

    private let lock = NSLock()
    /// Finished translations: "postId|targetTag" → translated text.
    private var translationCache: [String: String] = [:]
    /// Detection results: postId → (hash of the analyzed text, tag).
    /// The hash invalidates the entry when a post is edited in place.
    private var detectionCache: [String: (textHash: Int, tag: String?)] = [:]

    private init() {}

    // MARK: - Translation cache

    func cachedTranslation(postId: String, targetTag: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return translationCache["\(postId)|\(targetTag)"]
    }

    func storeTranslation(_ text: String, postId: String, targetTag: String) {
        lock.lock()
        defer { lock.unlock() }
        translationCache["\(postId)|\(targetTag)"] = text
    }

    // MARK: - Language detection

    /// Short tags the inline feature is willing to translate between.
    /// ko/fr/es posts exist in the wild, but the flagship pair is ja↔zh;
    /// pairs outside this set hide the button instead of guessing.
    private static let supportedTags: Set<String> = ["zh", "ja", "en"]

    /// (source, target) short tags for a post body under the given UI
    /// language, or nil when no translate button should appear.
    func translationPair(
        postId: String,
        text: String,
        serverLanguageTag: String,
        uiLanguage: AppLanguage
    ) -> (source: String, target: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }

        let target: String
        switch AppLanguage.resolved(from: uiLanguage.rawValue) {
        case .zh: target = "zh"
        case .ja: target = "ja"
        case .en: target = "en"
        case .system: return nil // resolved(from:) never returns .system
        }

        guard let source = sourceTag(postId: postId, text: trimmed, serverLanguageTag: serverLanguageTag),
              source != target else { return nil }
        return (source, target)
    }

    private func sourceTag(postId: String, text: String, serverLanguageTag: String) -> String? {
        let hash = text.hashValue
        lock.lock()
        if let hit = detectionCache[postId], hit.textHash == hash {
            lock.unlock()
            return hit.tag
        }
        lock.unlock()

        // Detection runs outside the lock: NLLanguageRecognizer is cheap on
        // a ≤400-char sample but there is no reason to serialize other
        // cache readers behind it.
        let tag = Self.detectSourceTag(text: text, serverLanguageTag: serverLanguageTag)

        lock.lock()
        detectionCache[postId] = (hash, tag)
        lock.unlock()
        return tag
    }

    private static func detectSourceTag(text: String, serverLanguageTag: String) -> String? {
        // 1. Trust the server tag when it names a concrete language.
        let server = serverLanguageTag.lowercased()
        if !server.isEmpty, server != "multi" {
            for tag in supportedTags where server.hasPrefix(tag) { return tag }
            return nil // concrete but outside the inline pairs (ko/fr/es…)
        }

        let sample = String(text.prefix(400))

        // 2. Kana is a near-certain Japanese signal and sidesteps the
        //    classic zh/ja confusion NLLanguageRecognizer has with
        //    kanji-only strings.
        if sample.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
            return "ja"
        }

        // 3. Constrained recognizer for everything else. The confidence
        //    floor keeps ambiguous short strings from flashing a bogus
        //    translate button.
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.japanese, .simplifiedChinese, .traditionalChinese, .english]
        recognizer.processString(sample)
        guard let dominant = recognizer.dominantLanguage,
              (recognizer.languageHypotheses(withMaximum: 4)[dominant] ?? 0) >= 0.5 else {
            return nil
        }
        switch dominant {
        case .japanese: return "ja"
        case .simplifiedChinese, .traditionalChinese: return "zh"
        case .english: return "en"
        default: return nil
        }
    }

    /// BCP-47 identifier the Translation framework expects for a short tag.
    static func localeIdentifier(forTag tag: String) -> String {
        tag == "zh" ? "zh-Hans" : tag
    }
}
