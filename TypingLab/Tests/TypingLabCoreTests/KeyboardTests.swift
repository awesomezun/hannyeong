import XCTest
@testable import TypingLabCore

final class KeyboardTests: XCTestCase {
    func testMixedPhysicalKeysAndShift() throws {
        XCTAssertEqual(Keyboard.rawKeys(for:"안녕 slack에서 ㅋㅋㅠㅠ 까"),"dkssud slackdptj zzbb Rk")
        XCTAssertEqual(try Keyboard.strokes(for:"R?").map(\.code),[15,44])
        XCTAssertTrue(try Keyboard.strokes(for:"R?").allSatisfy(\.shift))
    }
    func testCanonicalHangulAndUnsupportedText() throws {
        XCTAssertEqual(Keyboard.rawKeys(for:"안녕".decomposedStringWithCanonicalMapping),"dkssud")
        XCTAssertThrowsError(try Keyboard.strokes(for:"🐥"))
    }
}
