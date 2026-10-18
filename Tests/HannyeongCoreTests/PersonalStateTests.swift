import Foundation
import XCTest
@testable import HannyeongCore

final class PersonalStateTests: XCTestCase {
    private let current = String(repeating: "a", count: 12) + "-current-model"
    private let previous = String(repeating: "b", count: 12) + "-previous-model"

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func write(_ modelID: String, revision: Int = 1, to url: URL) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: ["modelID": modelID, "revision": revision, "entries": []])
        try data.write(to: url)
        return data
    }

    func testSameModelFileIsUsed() throws {
        let directory = try folder()
        let file = directory.appendingPathComponent(PersonalState.fileName(for: current))
        let data = try write(current, revision: 7, to: file)
        let selection = try PersonalState.select(directory: directory, modelID: current)
        XCTAssertEqual(selection.url, file)
        XCTAssertEqual(selection.origin, .existing)
        XCTAssertNil(selection.migratedLegacy)
        XCTAssertEqual(selection.otherModelFiles, [])
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testOtherModelFileIsKeptAndNotApplied() throws {
        let directory = try folder()
        let old = directory.appendingPathComponent(PersonalState.fileName(for: previous))
        let data = try write(previous, to: old)
        let selection = try PersonalState.select(directory: directory, modelID: current)
        XCTAssertEqual(selection.url.lastPathComponent, "local-b3-session-personal-aaaaaaaaaaaa.json")
        XCTAssertEqual(selection.origin, .new)
        XCTAssertFalse(FileManager.default.fileExists(atPath: selection.url.path))
        XCTAssertEqual(selection.otherModelFiles, [old])
        XCTAssertEqual(try Data(contentsOf: old), data)
    }

    func testMissingFileStartsNew() throws {
        let directory = try folder().appendingPathComponent("Hannyeong")
        let selection = try PersonalState.select(directory: directory, modelID: current)
        XCTAssertEqual(selection.origin, .new)
        XCTAssertEqual(selection.otherModelFiles, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testLegacyFileOfCurrentModelIsRenamedUnchanged() throws {
        let directory = try folder()
        let legacy = directory.appendingPathComponent(PersonalState.legacyName)
        let data = try write(current, revision: 5, to: legacy)
        let selection = try PersonalState.select(directory: directory, modelID: current)
        XCTAssertEqual(selection.origin, .existing)
        XCTAssertEqual(selection.migratedLegacy, selection.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(try Data(contentsOf: selection.url), data)
    }

    func testLegacyFileOfAnotherModelIsRenamedToItsOwnModelAndKept() throws {
        let directory = try folder()
        let legacy = directory.appendingPathComponent(PersonalState.legacyName)
        let data = try write(previous, to: legacy)
        let backup = directory.appendingPathComponent("local-b3-session-personal.backup-devmodel-d5a3b950-2026-10-18.json")
        _ = try write("d5a3b950", to: backup)
        let selection = try PersonalState.select(directory: directory, modelID: current)
        let kept = directory.appendingPathComponent(PersonalState.fileName(for: previous))
        XCTAssertEqual(selection.origin, .new)
        XCTAssertEqual(selection.migratedLegacy, kept)
        XCTAssertEqual(try Data(contentsOf: kept), data)
        XCTAssertEqual(selection.otherModelFiles, [kept, backup])
        // A second launch finds nothing left to rename.
        let again = try PersonalState.select(directory: directory, modelID: current)
        XCTAssertNil(again.migratedLegacy)
        XCTAssertEqual(again.otherModelFiles, [kept, backup])
    }

    func testLegacyConflictFailsWithoutMovingEither() throws {
        let directory = try folder()
        let legacy = directory.appendingPathComponent(PersonalState.legacyName)
        let target = directory.appendingPathComponent(PersonalState.fileName(for: current))
        let legacyData = try write(current, revision: 1, to: legacy)
        let targetData = try write(current, revision: 2, to: target)
        XCTAssertThrowsError(try PersonalState.select(directory: directory, modelID: current)) {
            XCTAssertTrue($0.localizedDescription.contains("resolve them manually"))
        }
        XCTAssertEqual(try Data(contentsOf: legacy), legacyData)
        XCTAssertEqual(try Data(contentsOf: target), targetData)
    }

    func testPrefixCollisionWithDifferentFullModelIDFails() throws {
        let directory = try folder()
        let file = directory.appendingPathComponent(PersonalState.fileName(for: current))
        _ = try write(String(current.prefix(12)) + "-another", to: file)
        XCTAssertThrowsError(try PersonalState.select(directory: directory, modelID: current)) {
            XCTAssertTrue($0.localizedDescription.contains("belongs to model"))
        }
    }

    func testUnreadableLegacyFileFails() throws {
        let directory = try folder()
        try Data("{}".utf8).write(to: directory.appendingPathComponent(PersonalState.legacyName))
        XCTAssertThrowsError(try PersonalState.select(directory: directory, modelID: current)) {
            XCTAssertTrue($0.localizedDescription.contains("no readable modelID"))
        }
    }

    /// The three cases against the actual worker: the app path always starts it, the other model's file
    /// stays byte-identical, and handing that file to the worker directly still fails loudly.
    func testActualWorkerStartsInAllThreeCasesAndStillRejectsAnotherModelsFile() async throws {
        guard let path = ProcessInfo.processInfo.environment["HANNYEONG_LOCAL_RUNTIME"] else {
            throw XCTSkip("Set HANNYEONG_LOCAL_RUNTIME to exercise personal state selection with the actual worker")
        }
        let runtime = try JSONDecoder().decode(LocalRuntimeConfiguration.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)))
        let modelID = try PersonalState.modelID(ofModel: URL(fileURLWithPath: runtime.model))
        let candidates = try CandidateBuilder.candidates(for: "go", includeSplits: true)

        let same = try folder()
        let sameFile = same.appendingPathComponent(PersonalState.fileName(for: modelID))
        _ = try write(modelID, revision: 3, to: sameFile)
        let sameSelection = try PersonalState.select(directory: same, modelID: modelID)
        XCTAssertEqual(sameSelection.origin, .existing)
        let sameClient = LocalDecisionClient(runtime: runtime, personalURL: sameSelection.url)
        let sameClientInfo = try await sameClient.prepare()
        XCTAssertEqual(sameClientInfo.modelID, modelID)
        let update = try await sameClient.correct(raw: "go", before: "나는 설거지부터", candidates: candidates, preferred: "해")
        XCTAssertEqual(update.personalRevision, 4)

        let other = try folder()
        let legacy = other.appendingPathComponent(PersonalState.legacyName)
        let otherID = String(repeating: "0", count: 64)
        let otherData = try write(otherID, revision: 9, to: legacy)
        let otherSelection = try PersonalState.select(directory: other, modelID: modelID)
        XCTAssertEqual(otherSelection.origin, .new)
        let kept = other.appendingPathComponent(PersonalState.fileName(for: otherID))
        XCTAssertEqual(otherSelection.otherModelFiles, [kept])
        let otherClient = LocalDecisionClient(runtime: runtime, personalURL: otherSelection.url)
        let otherClientInfo = try await otherClient.prepare()
        XCTAssertEqual(otherClientInfo.modelID, modelID)
        _ = try await otherClient.correct(raw: "go", before: "나는 설거지부터", candidates: candidates, preferred: "해")
        XCTAssertEqual(try Data(contentsOf: kept), otherData)

        let direct = LocalDecisionClient(runtime: runtime, personalURL: kept)
        do {
            _ = try await direct.prepare()
            XCTFail("The worker accepted another model's personal state")
        } catch {
            let log = try String(contentsOf: other.appendingPathComponent("local-model.log"), encoding: .utf8)
            XCTAssertTrue(log.contains("Personal state belongs to a different model"))
        }
        XCTAssertEqual(try Data(contentsOf: kept), otherData)

        let missing = try folder().appendingPathComponent("Hannyeong")
        let missingSelection = try PersonalState.select(directory: missing, modelID: modelID)
        XCTAssertEqual(missingSelection.origin, .new)
        let missingClient = LocalDecisionClient(runtime: runtime, personalURL: missingSelection.url)
        let missingClientInfo = try await missingClient.prepare()
        XCTAssertEqual(missingClientInfo.modelID, modelID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingSelection.url.path))
    }
}
