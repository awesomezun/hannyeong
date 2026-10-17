import Foundation
import XCTest
@testable import HannyeongCore

final class CorrectionMemoryTests: XCTestCase {
    func testScopeCyclePreservesTextContextOtherEntriesAndPersistence() throws {
        var memory = CorrectionMemory()
        try memory.record(raw: "to", before: "오늘은", rejected: "to", preferred: "새", scope: .context)
        try memory.record(raw: "to", before: "다른 문맥", rejected: "새", preferred: "to", scope: .context)
        try memory.record(raw: "go", before: "인사", rejected: "해", preferred: "go", scope: .always)
        let original = memory.entries
        let always = try memory.changeScope(of: original[0], to: .always)
        XCTAssertEqual(memory.preferred(raw: "to", before: "무관한 문맥"), "새")
        XCTAssertEqual(always.raw, original[0].raw)
        XCTAssertEqual(always.before, original[0].before)
        XCTAssertEqual(always.preferred, original[0].preferred)
        XCTAssertEqual(always.rejected, original[0].rejected)
        XCTAssertEqual(Array(memory.entries.dropFirst()), Array(original.dropFirst()))
        memory = try JSONDecoder().decode(CorrectionMemory.self, from: JSONEncoder().encode(memory))
        let context = try memory.changeScope(of: always, to: .context)
        XCTAssertEqual(context, original[0])
        XCTAssertEqual(memory.entries, original)
        XCTAssertNil(memory.preferred(raw: "to", before: "무관한 문맥"))
        XCTAssertEqual(memory.preferred(raw: "to", before: "오늘은"), "새")
        XCTAssertThrowsError(try memory.changeScope(of: always, to: .context))
        XCTAssertEqual(memory.entries, original)
    }

    func testBulkRemovalKeepsUnselectedContextAndValidatesBeforeMutating() throws {
        var memory = CorrectionMemory()
        try memory.record(raw: "to", before: "", rejected: "새", preferred: "to", scope: .context)
        try memory.record(raw: "to", before: "다른 문맥", rejected: "to", preferred: "새", scope: .context)
        try memory.record(raw: "go", before: "", rejected: "해", preferred: "go", scope: .always)
        let original = memory.entries
        let missing = CorrectionExample(raw: "to", before: "없는 문맥", rejected: "새", preferred: "to", scope: .context)
        XCTAssertThrowsError(try memory.remove([original[0], missing]))
        XCTAssertEqual(memory.entries, original)
        try memory.remove([original[2], original[0]])
        XCTAssertEqual(memory.entries, [original[1]])
        XCTAssertEqual(memory.preferred(raw: "to", before: "다른 문맥"), "새")
        XCTAssertNil(memory.preferred(raw: "to", before: ""))
        XCTAssertNil(memory.preferred(raw: "go", before: ""))
        try memory.remove(memory.entries)
        XCTAssertTrue(memory.entries.isEmpty)
    }

    func testRemovalDeletesOnlySelectedContextAndSurvivesPersistence() throws {
        var memory = CorrectionMemory()
        try memory.record(raw: "to", before: "", rejected: "새", preferred: "to", scope: .context)
        try memory.record(raw: "to", before: "다른 문맥", rejected: "to", preferred: "새", scope: .context)
        try memory.record(raw: "go", before: "", rejected: "해", preferred: "go", scope: .always)
        let selected = memory.entries[0]
        let retained = Array(memory.entries.dropFirst())
        try memory.remove(selected)
        let restored = try JSONDecoder().decode(CorrectionMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(restored.entries, retained)
        XCTAssertNil(restored.preferred(raw: "to", before: ""))
        XCTAssertEqual(restored.preferred(raw: "to", before: "다른 문맥"), "새")
        XCTAssertEqual(restored.preferred(raw: "go", before: "아무 문맥"), "go")
        XCTAssertThrowsError(try memory.remove(selected))
        XCTAssertEqual(memory.entries, retained)
        try memory.remove(retained[1])
        XCTAssertNil(memory.preferred(raw: "go", before: "아무 문맥"))
        XCTAssertEqual(memory.entries, [retained[0]])
    }

    func testDecomposedContextIsStoredCanonicallyAndMatchesComposedInput() throws {
        var memory = CorrectionMemory()
        let before = "회의록은 ".decomposedStringWithCanonicalMapping
        try memory.record(raw: "craftdp", before: before, rejected: "craftdp", preferred: "craft에", scope: .context)
        XCTAssertEqual(memory.entries[0].before.utf16.count, "회의록은".utf16.count)
        XCTAssertEqual(memory.preferred(raw: "craftdp", before: "회의록은 "), "craft에")
        let restored = try JSONDecoder().decode(CorrectionMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(restored.preferred(raw: "craftdp", before: before), "craft에")
    }

    func testContextPreferenceSurvivesPersistenceWithoutApplyingElsewhere() throws {
        var memory = CorrectionMemory()
        try memory.record(raw: "go", before: " 오늘 안에 ", rejected: "go", preferred: "해", scope: .context)
        let restored = try JSONDecoder().decode(CorrectionMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(restored.entries, memory.entries)
        XCTAssertEqual(restored.preferred(raw: "go", before: "오늘 안에"), "해")
        XCTAssertNil(restored.preferred(raw: "go", before: "Let's"))
        XCTAssertNil(restored.preferred(raw: "to", before: "오늘 안에"))
    }

    func testRepeatedContextReplacesItsRecordAndRetainsNewestExamples() throws {
        var memory = CorrectionMemory()
        for index in 1...4 {
            try memory.record(raw: "go", before: "문맥 \(index)", rejected: "go", preferred: "해", scope: .context)
        }
        try memory.record(raw: "go", before: " 문맥 2\n", rejected: "해", preferred: "go", scope: .context)
        XCTAssertEqual(memory.entries.count, 4)
        XCTAssertEqual(memory.preferred(raw: "go", before: "문맥 2"), "go")
        XCTAssertEqual(memory.examples(for: "go").map(\.before), ["문맥 2", "문맥 4", "문맥 3"])
        XCTAssertEqual(memory.examples(for: "go").first?.rejected, "해")
    }

    func testAlwaysPreferenceRequiresExplicitScopeAndTakesPriority() throws {
        var memory = CorrectionMemory()
        try memory.record(raw: "go", before: "오늘 안에", rejected: "go", preferred: "해", scope: .context)
        try memory.record(raw: "go", before: "Let's", rejected: "해", preferred: "go", scope: .always)
        XCTAssertEqual(memory.preferred(raw: "go", before: "오늘 안에"), "go")
        XCTAssertEqual(memory.preferred(raw: "go", before: "다른 문맥"), "go")
        XCTAssertNil(memory.preferred(raw: "to", before: "Let's"))
        XCTAssertEqual(memory.examples(for: "go").map(\.scope), [.context])
        try memory.record(raw: "go", before: "새로운 문맥", rejected: "go", preferred: "해", scope: .always)
        XCTAssertEqual(memory.preferred(raw: "go", before: "Let's"), "해")
        XCTAssertEqual(memory.entries.filter { $0.scope == .always }.count, 1)
    }

    func testNewContextCorrectionRemovesAnOlderAlwaysPreferenceForTheSameRaw() throws {
        var memory = CorrectionMemory()
        try memory.record(raw: "go", before: "Let's", rejected: "해", preferred: "go", scope: .always)
        try memory.record(raw: "to", before: "새 문맥", rejected: "to", preferred: "새", scope: .always)
        try memory.record(raw: "go", before: "오늘 안에", rejected: "go", preferred: "해", scope: .context)
        XCTAssertEqual(memory.preferred(raw: "go", before: "오늘 안에"), "해")
        XCTAssertNil(memory.preferred(raw: "go", before: "Let's"))
        XCTAssertEqual(memory.preferred(raw: "to", before: "다른 문맥"), "새")
        XCTAssertEqual(memory.entries.filter { $0.raw == "go" }.map(\.scope), [.context])
    }

    func testContextUsesLast120CharactersWithoutCollapsingInternalWhitespace() throws {
        var memory = CorrectionMemory()
        let suffix = String(repeating: "가", count: 118) + " 나"
        try memory.record(raw: "go", before: "이전 문장" + suffix + " \n", rejected: "go", preferred: "해", scope: .context)
        XCTAssertEqual(memory.entries[0].before, suffix)
        XCTAssertEqual(memory.entries[0].before.count, 120)
        XCTAssertEqual(memory.preferred(raw: "go", before: "다른 이전 문장" + suffix), "해")
        XCTAssertNil(memory.preferred(raw: "go", before: suffix.replacingOccurrences(of: " 나", with: "  나")))
    }

    func testPreferredMustBeAComposedCandidateAndFailedRecordDoesNotChangeMemory() throws {
        var memory = CorrectionMemory()
        try memory.record(raw: "googlefh", before: "검색은", rejected: "googlefh", preferred: "google로", scope: .context)
        let original = memory.entries
        XCTAssertThrowsError(try memory.record(raw: "go", before: "", rejected: "go", preferred: "가", scope: .context))
        XCTAssertThrowsError(try memory.record(raw: "go!", before: "", rejected: "go!", preferred: "해!", scope: .context))
        XCTAssertEqual(memory.entries, original)
    }

    func testRequestOmitsEmptyFeedbackAndKeepsOriginalPromptAndStateShape() throws {
        let candidates = try CandidateBuilder.candidates(for: "go", includeSplits: true)
        let request = JevClient.request(raw: "go", before: "오늘 안에", candidates: candidates)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let state = try XCTUnwrap(object["state"] as? [String: Any])
        XCTAssertEqual(Set(state.keys), ["before", "raw", "candidates"])
        XCTAssertNil(request.state.corrections)
        XCTAssertEqual(request.questions["interpretation"]?.instructions, JevClient.instructions)
        let explicitEmpty = JevClient.request(raw: "go", before: "오늘 안에", candidates: candidates, corrections: [])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(request), try encoder.encode(explicitEmpty))
    }

    func testRequestIncludesExplicitCorrectionExamplesWithoutChangingCandidates() throws {
        let candidates = try CandidateBuilder.candidates(for: "go", includeSplits: true)
        let example = CorrectionExample(raw: "go", before: "오늘 안에", rejected: "go", preferred: "해", scope: .context)
        let request = JevClient.request(raw: "go", before: "다른 문맥", candidates: candidates, corrections: [example])
        let restored = try JSONDecoder().decode(JevRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(restored.state.corrections, [example])
        XCTAssertEqual(restored.state.before, "다른 문맥")
        XCTAssertEqual(restored.state.candidates, Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.text) }))
        let prompt = try XCTUnwrap(restored.questions["interpretation"]?.instructions)
        XCTAssertTrue(prompt.contains("prioritize its preferred text"))
        XCTAssertTrue(prompt.contains("without blindly applying"))
    }
}
