import XCTest
@testable import TypingLabCore

final class ComparisonTests: XCTestCase {
    func testComparisonIgnoresCanonicalFormAndCommitSpace() {
        XCTAssertTrue(Comparison.matches("안녕ㅋㅋ", "안녕ㅋㅋ ".decomposedStringWithCanonicalMapping))
        XCTAssertFalse(Comparison.matches("slack에서", "slack 에서"))
    }
    func testDiffShowsSubstitutionInsertionAndDeletion() {
        let substitution = Comparison.differences("slack", "님차")
        XCTAssertEqual(substitution.expected.filter(\.changed).map(\.text).joined(), "slack")
        XCTAssertEqual(substitution.actual.filter(\.changed).map(\.text).joined(), "님차")
        XCTAssertEqual(Comparison.differences("api", "apiㅋ").actual.filter(\.changed).map(\.text).joined(), "ㅋ")
        XCTAssertEqual(Comparison.differences("안녕", "안").expected.filter(\.changed).map(\.text).joined(), "녕")
    }
}
