import Foundation
import XCTest
@testable import HannyeongCore

final class LocalDecisionIntegrationTests: XCTestCase {
    func testScopeCycleUpdatesAnotherWorkerWithoutRetrainingOrChangingOtherCorrections() async throws {
        guard let path = ProcessInfo.processInfo.environment["HANNYEONG_LOCAL_RUNTIME"] else {
            throw XCTSkip("Set HANNYEONG_LOCAL_RUNTIME to exercise scope changes in the actual local model")
        }
        let runtime = try JSONDecoder().decode(LocalRuntimeConfiguration.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let personal = folder.appendingPathComponent("personal.json")
        let writer = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let watcher = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let candidates = try CandidateBuilder.candidates(for: "to", includeSplits: true)
        let outside = try await watcher.decide(raw: "to", before: "Let's", candidates: candidates)
        let preferred = try XCTUnwrap(candidates.first { $0.text != outside.predicted }).text
        let entry = CorrectionExample(raw: "to", before: "오늘은", rejected: outside.predicted,
                                      preferred: preferred, scope: .context)
        _ = try await writer.correct(raw: entry.raw, before: entry.before, candidates: candidates,
                                     preferred: entry.preferred, scope: entry.scope)
        _ = try await writer.correct(raw: "hello", before: "인사는",
            candidates: CandidateBuilder.candidates(for: "hello", includeSplits: true), preferred: "hello")
        let before = try JSONSerialization.jsonObject(with: Data(contentsOf: personal)) as! [String: Any]
        let update = try await writer.changeScope(of: entry, to: .always)
        var expected = before["entries"] as! [[String: Any]]
        expected[0]["scope"] = "always"
        let changed = try JSONSerialization.jsonObject(with: Data(contentsOf: personal)) as! [String: Any]
        XCTAssertTrue(NSArray(array: changed["entries"] as! [Any]).isEqual(to: expected))
        XCTAssertEqual(update.personalRevision, (before["revision"] as! Int) + 1)
        let global = try await watcher.decide(raw: entry.raw, before: "Let's", candidates: candidates)
        XCTAssertEqual(global.predicted, preferred)
        let restarted = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let persisted = try await restarted.decide(raw: entry.raw, before: "Let's", candidates: candidates)
        XCTAssertEqual(persisted.predicted, preferred)
        let always = CorrectionExample(raw: entry.raw, before: entry.before, rejected: entry.rejected,
                                       preferred: entry.preferred, scope: .always)
        let restore = try await writer.changeScope(of: always, to: .context)
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: personal)) as! [String: Any]
        XCTAssertTrue(NSArray(array: after["entries"] as! [Any]).isEqual(to: before["entries"] as! [Any]))
        XCTAssertEqual(restore.personalRevision, update.personalRevision + 1)
        let restored = try await watcher.decide(raw: entry.raw, before: "Let's", candidates: candidates)
        XCTAssertEqual(restored.predicted, outside.predicted)
        for (id, value) in outside.probabilities {
            XCTAssertEqual(value, try XCTUnwrap(restored.probabilities[id]), accuracy: 0.00001)
        }
        let sameContext = try await watcher.decide(raw: entry.raw, before: entry.before, candidates: candidates)
        XCTAssertEqual(sameContext.predicted, preferred)
    }

    func testBulkRemovalUsesOneRevisionAndPreservesUnselectedWeights() async throws {
        guard let path = ProcessInfo.processInfo.environment["HANNYEONG_LOCAL_RUNTIME"] else {
            throw XCTSkip("Set HANNYEONG_LOCAL_RUNTIME to exercise bulk removal in the actual local model")
        }
        let runtime = try JSONDecoder().decode(LocalRuntimeConfiguration.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let personal = folder.appendingPathComponent("personal.json")
        let writer = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let watcher = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let to = try CandidateBuilder.candidates(for: "to", includeSplits: true)
        let base = try await watcher.decide(raw: "to", before: "", candidates: to)
        let target = try XCTUnwrap(to.first { $0.text != base.predicted })
        let selected = [
            CorrectionExample(raw: "to", before: "", rejected: base.predicted, preferred: target.text, scope: .context),
            CorrectionExample(raw: "to", before: "다른 문맥", rejected: "to", preferred: "새", scope: .context),
            CorrectionExample(raw: "go", before: "Always", rejected: "해", preferred: "go", scope: .always)
        ]
        for entry in selected {
            _ = try await writer.correct(raw: entry.raw, before: entry.before,
                candidates: CandidateBuilder.candidates(for: entry.raw, includeSplits: true),
                preferred: entry.preferred, scope: entry.scope)
        }
        let hello = try CandidateBuilder.candidates(for: "hello", includeSplits: true)
        _ = try await writer.correct(raw: "hello", before: "인사는", candidates: hello, preferred: "hello")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: personal)) as! [String: Any]
        let retained = (saved["entries"] as! [[String: Any]]).filter { $0["raw"] as? String == "hello" }
        let corrected = try await watcher.decide(raw: "to", before: "", candidates: to)
        XCTAssertEqual(corrected.predicted, target.text)
        let removal = try await writer.forget(selected)
        XCTAssertEqual(removal.removedCount, 3)
        XCTAssertEqual(removal.personalRevision, corrected.personalRevision + 1)
        let restored = try await watcher.decide(raw: "to", before: "", candidates: to)
        XCTAssertEqual(restored.predicted, base.predicted)
        for (key, value) in base.probabilities {
            XCTAssertEqual(value, try XCTUnwrap(restored.probabilities[key]), accuracy: 0.00001)
        }
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: personal)) as! [String: Any]
        XCTAssertTrue(NSArray(array: after["entries"] as! [Any]).isEqual(to: retained))
        let restarted = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let persistent = try await restarted.decide(raw: "hello", before: "인사는", candidates: hello)
        XCTAssertEqual(persistent.predicted, "hello")
        let last = CorrectionExample(raw: "hello", before: "인사는", rejected: "", preferred: "hello", scope: .context)
        let allRemoval = try await writer.forget([last])
        XCTAssertEqual(allRemoval.removedCount, 1)
        let empty = try JSONSerialization.jsonObject(with: Data(contentsOf: personal)) as! [String: Any]
        XCTAssertTrue((empty["entries"] as! [Any]).isEmpty)
    }

    func testRemovalRestoresBaseScoresInAnotherRunningWorkerAndKeepsOtherCorrections() async throws {
        guard let path = ProcessInfo.processInfo.environment["HANNYEONG_LOCAL_RUNTIME"] else {
            throw XCTSkip("Set HANNYEONG_LOCAL_RUNTIME to exercise removal in the actual local model")
        }
        let runtime = try JSONDecoder().decode(LocalRuntimeConfiguration.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let personal = folder.appendingPathComponent("personal.json")
        let writer = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let watcher = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let candidates = try CandidateBuilder.candidates(for: "to", includeSplits: true)
        let original = try await watcher.decide(raw: "to", before: "", candidates: candidates)
        let target = try XCTUnwrap(candidates.first { $0.text != original.predicted })
        _ = try await writer.correct(raw: "to", before: "", candidates: candidates, preferred: target.text)
        _ = try await writer.correct(raw: "to", before: "다른 문맥", candidates: candidates, preferred: "새")
        let corrected = try await watcher.decide(raw: "to", before: "", candidates: candidates)
        XCTAssertEqual(corrected.predicted, target.text)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: personal)) as! [String: Any]
        let retained = (saved["entries"] as! [[String: Any]]).filter { $0["before"] as? String != "" }
        let removal = try await writer.forget(raw: "to", before: "", preferred: target.text, scope: .context)
        XCTAssertEqual(removal.removedCount, 1)
        XCTAssertEqual(removal.personalRevision, corrected.personalRevision + 1)
        let restored = try await watcher.decide(raw: "to", before: "", candidates: candidates)
        XCTAssertEqual(restored.predicted, original.predicted)
        for (key, value) in original.probabilities {
            XCTAssertEqual(value, try XCTUnwrap(restored.probabilities[key]), accuracy: 0.00001)
        }
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: personal)) as! [String: Any]
        XCTAssertTrue(NSArray(array: after["entries"] as! [Any]).isEqual(to: retained))
        let outside = try await watcher.decide(raw: "to", before: "다른 문맥", candidates: candidates)
        XCTAssertEqual(outside.predicted, "새")
        let restarted = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let persistent = try await restarted.decide(raw: "to", before: "", candidates: candidates)
        XCTAssertEqual(persistent.predicted, original.predicted)
        let go = try CandidateBuilder.candidates(for: "go", includeSplits: true)
        _ = try await writer.correct(raw: "go", before: "Always", candidates: go, preferred: "go", scope: .always)
        let alwaysRemoval = try await writer.forget(raw: "go", before: "Always", preferred: "go", scope: .always)
        XCTAssertEqual(alwaysRemoval.removedCount, 1)
        let final = try JSONSerialization.jsonObject(with: Data(contentsOf: personal)) as! [String: Any]
        XCTAssertTrue(NSArray(array: final["entries"] as! [Any]).isEqual(to: retained))
    }

    func testRealModelOrderImmediateUpdateAndRestartPersistence() async throws {
        guard let path = ProcessInfo.processInfo.environment["HANNYEONG_LOCAL_RUNTIME"] else {
            throw XCTSkip("Set HANNYEONG_LOCAL_RUNTIME to exercise the actual trained local model")
        }
        let runtime = try JSONDecoder().decode(LocalRuntimeConfiguration.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let personal = folder.appendingPathComponent("personal.json")
        let client = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let candidates = try CandidateBuilder.candidates(for: "go", includeSplits: true)
        let before = "나는 설거지부터 "
        let original = try await client.decide(raw: "go", before: before, candidates: candidates)
        let reversed = try await client.decide(raw: "go", before: before, candidates: candidates.reversed())
        XCTAssertEqual(original.predicted, reversed.predicted)
        for (key, value) in original.probabilities {
            XCTAssertEqual(value, try XCTUnwrap(reversed.probabilities[key]), accuracy: 0.00001)
        }
        // Correct to the least likely candidate to verify a real numerical update,
        // including when the base model already chooses the desired language.
        let target = try XCTUnwrap(candidates.min { original.probabilities[$0.id]! < original.probabilities[$1.id]! })
        let update = try await client.correct(raw: "go", before: before, candidates: candidates, preferred: target.text)
        XCTAssertEqual(update.personalRevision, 1)
        XCTAssertGreaterThan(update.afterProbability, update.beforeProbability)
        let next = try await client.decide(raw: "go", before: before, candidates: candidates)
        XCTAssertEqual(next.personalRevision, 1)
        XCTAssertEqual(next.predicted, target.text)
        XCTAssertGreaterThan(try XCTUnwrap(next.probabilities[target.id]), try XCTUnwrap(original.probabilities[target.id]))
        let restarted = LocalDecisionClient(runtime: runtime, personalURL: personal)
        let restored = try await restarted.decide(raw: "go", before: before, candidates: candidates)
        XCTAssertEqual(restored.personalRevision, 1)
        for (key, value) in next.probabilities {
            XCTAssertEqual(value, try XCTUnwrap(restored.probabilities[key]), accuracy: 0.00001)
        }
        let other = try CandidateBuilder.candidates(for: "hello", includeSplits: true)
        let fresh = LocalDecisionClient(runtime: runtime, personalURL: folder.appendingPathComponent("fresh.json"))
        let unchanged = try await client.decide(raw: "hello", before: "Say ", candidates: other)
        let comparison = try await fresh.decide(raw: "hello", before: "Say ", candidates: other)
        XCTAssertEqual(unchanged.predicted, comparison.predicted)
        for (key, value) in unchanged.probabilities {
            XCTAssertEqual(value, try XCTUnwrap(comparison.probabilities[key]), accuracy: 0.00001)
        }
        _ = try await client.correct(raw: "go", before: "Always", candidates: candidates,
                                     preferred: "go", scope: .always)
        _ = try await client.correct(raw: "go", before: before, candidates: candidates,
                                     preferred: "해", scope: .context)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: personal)) as! [String: Any]
        let entries = saved["entries"] as! [[String: Any]]
        XCTAssertFalse(entries.contains { $0["raw"] as? String == "go" && $0["scope"] as? String == "always" })
    }
}
