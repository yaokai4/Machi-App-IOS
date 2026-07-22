import Foundation
import Testing
@testable import Machi

@MainActor
struct JLPTOfficialScoreTests {
    @Test func paperResultDecodesExactOfficialScoreContract() throws {
        let result = try JSONDecoder().decode(KaiXJLPTPaperResult.self, from: Data(#"""
        {
          "status":"ok",
          "paperId":"n2-paper",
          "level":"N2",
          "officialScore":{
            "mode":"jlpt_scaled_reference",
            "level":"N2",
            "total":112,
            "totalMax":180,
            "passLine":90,
            "passedReference":true,
            "divisions":[
              {"key":"language","label":"SERVER LANGUAGE","raw":22,"rawMax":30,"scaled":44,"scaledMax":60,"sectionMin":19,"passed":true},
              {"key":"reading","label":"SERVER READING","raw":18,"rawMax":30,"scaled":36,"scaledMax":60,"sectionMin":19,"passed":true},
              {"key":"listening","label":"SERVER LISTENING","raw":16,"rawMax":30,"scaled":32,"scaledMax":60,"sectionMin":19,"passed":true}
            ],
            "note":"SERVER NOTE MUST NOT BE DISPLAYED"
          }
        }
        """#.utf8))

        let score = try #require(result.officialScore)
        #expect(score.mode == "jlpt_scaled_reference")
        #expect(score.total == 112)
        #expect(score.totalMax == 180)
        #expect(score.passLine == 90)
        #expect(score.passedReference)
        #expect(score.divisions.map(\.key) == ["language", "reading", "listening"])
        #expect(score.divisions.last?.sectionMin == 19)
    }

    @Test func n1ThroughN3UseThreeLocalizedDivisionsAndIgnoreServerCopy() throws {
        let score = makeScore(
            level: "N2",
            keys: ["listening", "language", "reading"],
            serverLabel: "SERVER LABEL MUST NOT DISPLAY"
        )
        let presentation = try #require(
            JLPTOfficialScorePresentation.make(score: score, language: .en)
        )

        #expect(presentation.divisions.map(\.key) == ["language", "reading", "listening"])
        #expect(presentation.divisions.map(\.label) == [
            "Language Knowledge", "Reading", "Listening"
        ])
        #expect(!presentation.divisions.contains { $0.label.contains("SERVER") })
        #expect(!presentation.referenceNote.contains("SERVER"))
    }

    @Test func n4AndN5UseCombinedWrittenAndListeningDivisions() throws {
        let score = makeScore(
            level: "N5",
            keys: ["listening", "language_reading"],
            serverLabel: "サーバー"
        )
        let presentation = try #require(
            JLPTOfficialScorePresentation.make(score: score, language: .ja)
        )

        #expect(presentation.divisions.map(\.key) == ["language_reading", "listening"])
        #expect(presentation.divisions.map(\.label) == ["言語知識・読解", "聴解"])
    }

    @Test func officialPresentationFailsClosedForMissingDuplicateOrUnknownDivisions() {
        let malformed: [KaiXJLPTOfficialPaperScore] = [
            makeScore(level: "N2", keys: ["language", "reading"], serverLabel: "x"),
            makeScore(level: "N2", keys: ["language", "reading", "reading"], serverLabel: "x"),
            makeScore(level: "N2", keys: ["language", "reading", "future"], serverLabel: "x"),
            makeScore(level: "N5", keys: ["language", "listening"], serverLabel: "x")
        ]

        for score in malformed {
            #expect(JLPTOfficialScorePresentation.make(score: score, language: .zh) == nil)
        }
    }

    @Test func officialPresentationFailsClosedForInconsistentScoreMath() {
        let valid = makeScore(
            level: "N2",
            keys: ["language", "reading", "listening"],
            serverLabel: "x"
        )
        let first = valid.divisions[0]
        let malformedFirsts = [
            replacing(first, raw: -1),
            replacing(first, raw: first.rawMax + 1),
            replacing(first, rawMax: 0),
            replacing(first, scaled: -1),
            replacing(first, scaled: first.sectionMin - 1),
            replacing(first, scaled: first.scaledMax + 1),
            replacing(first, scaledMax: 0),
            replacing(first, scaledMax: first.scaledMax + 1),
            replacing(first, sectionMin: -1),
            replacing(first, sectionMin: first.scaledMax + 1),
            replacing(first, passed: false)
        ]
        var malformed = malformedFirsts.map { replacement in
            replacing(valid, divisions: [replacement] + Array(valid.divisions.dropFirst()))
        }
        malformed.append(replacing(valid, total: valid.total + 1))
        malformed.append(replacing(valid, total: -1))
        malformed.append(replacing(valid, total: valid.totalMax + 1))
        malformed.append(replacing(valid, passLine: 0))
        malformed.append(replacing(valid, passLine: valid.totalMax + 1))
        malformed.append(replacing(valid, passedReference: false))

        for score in malformed {
            #expect(JLPTOfficialScorePresentation.make(score: score, language: .en) == nil)
        }
    }

    @Test func partialOfficialScoreDTOFailsDecodeInsteadOfPresentingPartialData() {
        let data = Data(#"""
        {
          "status":"ok",
          "officialScore":{
            "mode":"jlpt_scaled_reference",
            "level":"N2",
            "total":90,
            "totalMax":180,
            "passLine":90,
            "passedReference":true,
            "divisions":[]
          }
        }
        """#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KaiXJLPTPaperResult.self, from: data)
        }
    }

    @Test func fullPaperReferenceDisclaimerIsAlwaysLocalTrilingualCopy() throws {
        let score = makeScore(
            level: "N5",
            keys: ["language_reading", "listening"],
            serverLabel: "x"
        )

        let zh = try #require(JLPTOfficialScorePresentation.make(score: score, language: .zh))
        let ja = try #require(JLPTOfficialScorePresentation.make(score: score, language: .ja))
        let en = try #require(JLPTOfficialScorePresentation.make(score: score, language: .en))
        #expect(zh.referenceNote.contains("线性折算"))
        #expect(zh.referenceNote.contains("等化"))
        #expect(ja.referenceNote.contains("線形"))
        #expect(ja.referenceNote.contains("等化済み尺度得点"))
        #expect(en.referenceNote.contains("linear reference"))
        #expect(en.referenceNote.contains("equated scaled scores"))
    }

    private func makeScore(
        level: String,
        keys: [String],
        serverLabel: String
    ) -> KaiXJLPTOfficialPaperScore {
        let divisions = keys.map { key in
            KaiXJLPTOfficialScoreDivision(
                key: key,
                label: serverLabel,
                raw: 10,
                rawMax: 20,
                scaled: 30,
                scaledMax: key == "language_reading" ? 120 : 60,
                sectionMin: 19,
                passed: true
            )
        }
        let total = divisions.reduce(0) { $0 + $1.scaled }
        let passLine = 90
        return KaiXJLPTOfficialPaperScore(
            mode: "jlpt_scaled_reference",
            level: level,
            total: total,
            totalMax: 180,
            passLine: passLine,
            passedReference: total >= passLine,
            divisions: divisions,
            note: "SERVER NOTE MUST NOT DISPLAY"
        )
    }

    private func replacing(
        _ division: KaiXJLPTOfficialScoreDivision,
        raw: Int? = nil,
        rawMax: Int? = nil,
        scaled: Int? = nil,
        scaledMax: Int? = nil,
        sectionMin: Int? = nil,
        passed: Bool? = nil
    ) -> KaiXJLPTOfficialScoreDivision {
        KaiXJLPTOfficialScoreDivision(
            key: division.key,
            label: division.label,
            raw: raw ?? division.raw,
            rawMax: rawMax ?? division.rawMax,
            scaled: scaled ?? division.scaled,
            scaledMax: scaledMax ?? division.scaledMax,
            sectionMin: sectionMin ?? division.sectionMin,
            passed: passed ?? division.passed
        )
    }

    private func replacing(
        _ score: KaiXJLPTOfficialPaperScore,
        total: Int? = nil,
        passLine: Int? = nil,
        passedReference: Bool? = nil,
        divisions: [KaiXJLPTOfficialScoreDivision]? = nil
    ) -> KaiXJLPTOfficialPaperScore {
        KaiXJLPTOfficialPaperScore(
            mode: score.mode,
            level: score.level,
            total: total ?? score.total,
            totalMax: score.totalMax,
            passLine: passLine ?? score.passLine,
            passedReference: passedReference ?? score.passedReference,
            divisions: divisions ?? score.divisions,
            note: score.note
        )
    }
}
