import XCTest
@testable import HannyeongCore

final class CompositionTests: XCTestCase {
    func testTwoSetCompositionAndShift() throws {
        for (raw, expected) in [("dkssud", "안녕"), ("gksrmf", "한글"),
                                ("rksk", "가나"), ("rkqt", "값"), ("Rk", "까")] {
            XCTAssertEqual(try HangulComposer.compose(raw), expected, raw)
        }
    }

    func testReplayingAfterBackspaceSeparatesFinalConsonant() throws {
        XCTAssertEqual(try HangulComposer.compose("rkqt"), "값")
        XCTAssertEqual(try HangulComposer.compose("rkq"), "갑")
        XCTAssertEqual(try HangulComposer.compose("rk"), "가")
        XCTAssertEqual(try HangulComposer.compose("r"), "ㄱ")
    }

    func testEnglishPrefixIsNotFedIntoKoreanSuffixComposition() throws {
        let candidates = try CandidateBuilder.candidates(for: "googlefh", includeSplits: true)
        XCTAssertEqual(candidates.first(where: { $0.splitIndex == 6 })?.text, "google로")
        XCTAssertTrue(candidates.contains(where: { $0.text == "googlefh" }))
        XCTAssertFalse(try CandidateBuilder.candidates(for: "googlefh", includeSplits: false)
            .contains(where: { $0.text == "google로" }))
    }

    func testAmbiguousKeysKeepBothReadings() throws {
        XCTAssertEqual(try CandidateBuilder.candidates(for: "go", includeSplits: false).map(\.text), ["go", "해"])
        XCTAssertEqual(try CandidateBuilder.candidates(for: "to", includeSplits: false).map(\.text), ["to", "새"])
    }
}
