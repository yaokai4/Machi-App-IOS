import Foundation

/// Validated, localized UI model for the full 180-point reference score.
/// Server labels and notes are intentionally never copied into presentation.
struct JLPTOfficialScorePresentation: Equatable {
    struct Division: Equatable, Identifiable {
        let key: String
        let label: String
        let raw: Int
        let rawMax: Int
        let scaled: Int
        let scaledMax: Int
        let sectionMin: Int
        let passed: Bool
        var id: String { key }
    }

    let level: String
    let total: Int
    let totalMax: Int
    let passLine: Int
    let passedReference: Bool
    let divisions: [Division]
    let referenceNote: String

    static func make(
        score: KaiXJLPTOfficialPaperScore,
        language: AppLanguage
    ) -> JLPTOfficialScorePresentation? {
        let level = score.level.uppercased()
        let expectedKeys: [String]
        switch level {
        case "N1", "N2", "N3":
            expectedKeys = ["language", "reading", "listening"]
        case "N4", "N5":
            expectedKeys = ["language_reading", "listening"]
        default:
            return nil
        }

        let keys = score.divisions.map(\.key)
        guard score.mode == "jlpt_scaled_reference",
              score.totalMax == 180,
              (0...score.totalMax).contains(score.total),
              (1...score.totalMax).contains(score.passLine),
              Set(keys).count == keys.count,
              Set(keys) == Set(expectedKeys) else { return nil }

        let divisionsAreValid = score.divisions.allSatisfy { division in
            division.rawMax > 0
                && (0...division.rawMax).contains(division.raw)
                && (1...score.totalMax).contains(division.scaledMax)
                && (0...division.scaledMax).contains(division.scaled)
                && (0...division.scaledMax).contains(division.sectionMin)
                && division.passed == (division.scaled >= division.sectionMin)
        }
        guard divisionsAreValid,
              score.divisions.reduce(0, { $0 + $1.scaledMax }) == score.totalMax,
              score.divisions.reduce(0, { $0 + $1.scaled }) == score.total,
              score.passedReference == (
                  score.total >= score.passLine
                      && score.divisions.allSatisfy(\.passed)
              ) else { return nil }

        let byKey = Dictionary(uniqueKeysWithValues: score.divisions.map { ($0.key, $0) })
        let localized = resolved(language)
        let divisions = expectedKeys.compactMap { key -> Division? in
            guard let source = byKey[key], let label = label(for: key, language: localized) else {
                return nil
            }
            return Division(
                key: source.key,
                label: label,
                raw: source.raw,
                rawMax: source.rawMax,
                scaled: source.scaled,
                scaledMax: source.scaledMax,
                sectionMin: source.sectionMin,
                passed: source.passed
            )
        }
        guard divisions.count == expectedKeys.count else { return nil }

        return JLPTOfficialScorePresentation(
            level: level,
            total: score.total,
            totalMax: score.totalMax,
            passLine: score.passLine,
            passedReference: score.passedReference,
            divisions: divisions,
            referenceNote: referenceNote(language: localized)
        )
    }

    private static func resolved(_ language: AppLanguage) -> AppLanguage {
        language == .system ? .resolved(from: AppLanguage.system.rawValue) : language
    }

    private static func label(for key: String, language: AppLanguage) -> String? {
        switch (key, language) {
        case ("language", .zh): "语言知识（文字・词汇・语法）"
        case ("language", .ja): "言語知識（文字・語彙・文法）"
        case ("language", .en): "Language Knowledge"
        case ("reading", .zh): "读解"
        case ("reading", .ja): "読解"
        case ("reading", .en): "Reading"
        case ("language_reading", .zh): "语言知识・读解"
        case ("language_reading", .ja): "言語知識・読解"
        case ("language_reading", .en): "Language Knowledge & Reading"
        case ("listening", .zh): "听解"
        case ("listening", .ja): "聴解"
        case ("listening", .en): "Listening"
        default: nil
        }
    }

    private static func referenceNote(language: AppLanguage) -> String {
        switch language {
        case .ja:
            "JLPT公式の得点区分に沿った線形の参考スコアです。公式試験は等化済み尺度得点を用いるため、学習の振り返り用としてご利用ください。"
        case .en:
            "A linear reference score following JLPT score divisions. The official test uses equated scaled scores; use this only for study review."
        case .zh, .system:
            "按 JLPT 官方得分区分线性折算的参考分；正式考试采用等化后的尺度分，仅供备考复盘，请以官方成绩为准。"
        }
    }
}
