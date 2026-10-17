import XCTest
@testable import HannyeongCore

final class RuleSelectorTests: XCTestCase {
    func testExternalFrequencyAndFixedMargin() {
        let selector = RuleSelector(lexicon: RuleLexicon(english: ["abc": 6], korean: ["가나": 4]))
        let result = selector.select(candidates: [Candidate(id: "x", text: "ABC"), Candidate(id: "y", text: "가나")], before: "")
        XCTAssertEqual(result.choice, "x")
        XCTAssertEqual(result.predicted, "ABC")
        XCTAssertEqual(result.score, 6)
        XCTAssertEqual(result.margin, 2)
        XCTAssertGreaterThanOrEqual(result.margin, RuleSelector.hybridMargin)
        XCTAssertEqual(RuleSelector.hybridMargin, 1.5)
    }

    func testKoreanSegmentationUsesPenalizedOptimum() {
        let selector = RuleSelector(lexicon: RuleLexicon(english: ["abc": 5.4], korean: ["가나": 4, "가": 6, "나": 6]))
        let result = selector.select(candidates: [Candidate(id: "a", text: "abc"), Candidate(id: "b", text: "가나")], before: "")
        XCTAssertEqual(result.choice, "b")
        XCTAssertEqual(result.ranking[0].lexical, 5.5, accuracy: 0.0001)
        XCTAssertEqual(result.margin, 0.1, accuracy: 0.0001)
        XCTAssertLessThan(result.margin, RuleSelector.hybridMargin)
    }

    func testMixedRunEvidenceIsWeightedAndBoundaryPenalized() {
        let selector = RuleSelector(lexicon: RuleLexicon(english: ["abc": 6], korean: ["가": 7]))
        let result = selector.select(candidates: [Candidate(id: "m", text: "abc가", splitIndex: 3)], before: "")
        XCTAssertEqual(result.ranking[0].lexical, (3 * 6.0 + 7) / 4 - 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.margin, 0)
    }

    func testContextPriorUsesOnlyLastFortyLettersAndIsBounded() {
        let selector = RuleSelector(lexicon: RuleLexicon(english: ["abc": 5], korean: ["가나": 5]))
        let candidates = [Candidate(id: "e", text: "abc"), Candidate(id: "k", text: "가나")]
        let context = String(repeating: "a", count: 80) + String(repeating: "가 ", count: 40)
        let result = selector.select(candidates: candidates, before: context)
        XCTAssertEqual(result.choice, "k")
        XCTAssertEqual(result.ranking[0].contextPrior, 1)
        XCTAssertEqual(result.ranking[1].contextPrior, 0)
        XCTAssertEqual(result.margin, 1)
        XCTAssertLessThan(result.margin, RuleSelector.hybridMargin)
    }

    func testCandidateLabelsAndSplitMetadataDoNotChangeScores() {
        let selector = RuleSelector(lexicon: RuleLexicon(english: ["abc": 5], korean: ["가나": 4]))
        let original = selector.select(candidates: [Candidate(id: "one", text: "abc"), Candidate(id: "two", text: "가나")], before: "가")
        let renamed = selector.select(candidates: [Candidate(id: "unrelated", text: "abc", splitIndex: 99),
                                                   Candidate(id: "opaque", text: "가나", splitIndex: 1)], before: "가")
        XCTAssertEqual(original.ranking.map(\.score), renamed.ranking.map(\.score))
        XCTAssertEqual(original.predicted, renamed.predicted)
    }

    func testUnknownSpansAndUnfinishedJamoHaveNoFrequencyEvidence() {
        let selector = RuleSelector(lexicon: RuleLexicon(english: [:], korean: [:]))
        let result = selector.select(candidates: [Candidate(id: "a", text: "가나다"), Candidate(id: "b", text: "ㄱㄴㄷ")], before: "")
        XCTAssertEqual(result.ranking.map(\.lexical), [0, 0])
        XCTAssertEqual(result.choice, "a", "Ties preserve the supplied candidate order.")
        XCTAssertEqual(result.margin, 0)
    }
}
