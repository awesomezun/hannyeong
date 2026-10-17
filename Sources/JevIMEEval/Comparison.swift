import Foundation
import JevIMECore

private struct ComparisonCase: Codable {
    let id: String
    let category: String
    let before: String
    let raw: String
    let acceptable: [String]
    let plausible: [String]
    let note: String
}

private struct ModeResult: Codable {
    let predicted: String
    let correct: Bool
    let route: String
    let latencyMilliseconds: Double
    let apiLatencyMilliseconds: Double?
    let rule: RuleDecision?
    let answer: JevAnswer?
    let usage: JevUsage?
}

private struct ComparisonRow: Codable {
    let test: ComparisonCase
    let candidates: [Candidate]
    var modes: [String: ModeResult]
}

private struct SubsetAccuracy: Codable {
    let completed: Int
    let correct: Int
    let accuracy: Double?

    init(_ results: [ModeResult]) {
        completed = results.count
        correct = results.filter(\.correct).count
        accuracy = completed == 0 ? nil : Double(correct) / Double(completed)
    }
}

private struct ModeSummary: Codable {
    let overall: SubsetAccuracy
    let singleAcceptable: SubsetAccuracy
    let multipleAcceptable: SubsetAccuracy
    let multiplePlausible: SubsetAccuracy
    let contextResolvedCompetition: SubsetAccuracy
    let categories: [String: SubsetAccuracy]
    let apiRequests: Int
    let inputTokens: Int
    let outputTokens: Int
    let meanMilliseconds: Double?
    let p50Milliseconds: Double?
    let p95Milliseconds: Double?
    let maxMilliseconds: Double?

    init(rows: [ComparisonRow], mode: String) {
        let completed = rows.filter { $0.modes[mode] != nil }
        func results(_ subset: [ComparisonRow]) -> [ModeResult] { subset.compactMap { $0.modes[mode] } }
        let all = results(completed)
        overall = SubsetAccuracy(all)
        singleAcceptable = SubsetAccuracy(results(completed.filter { $0.test.acceptable.count == 1 }))
        multipleAcceptable = SubsetAccuracy(results(completed.filter { $0.test.acceptable.count > 1 }))
        multiplePlausible = SubsetAccuracy(results(completed.filter { $0.test.plausible.count >= 2 }))
        contextResolvedCompetition = SubsetAccuracy(results(completed.filter {
            $0.test.plausible.count >= 2 && $0.test.acceptable.count == 1
        }))
        categories = Dictionary(grouping: completed, by: { $0.test.category }).mapValues {
            SubsetAccuracy(results($0))
        }
        apiRequests = all.filter { $0.route == "jev" }.count
        inputTokens = all.reduce(0) { $0 + ($1.usage?.inputTokens ?? 0) }
        outputTokens = all.reduce(0) { $0 + ($1.usage?.outputTokens ?? 0) }
        let times = all.map(\.latencyMilliseconds).sorted()
        func percentile(_ fraction: Double) -> Double? {
            times.isEmpty ? nil : times[max(0, Int(ceil(Double(times.count) * fraction)) - 1)]
        }
        meanMilliseconds = times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
        p50Milliseconds = percentile(0.5)
        p95Milliseconds = percentile(0.95)
        maxMilliseconds = times.last
    }
}

private struct ComparisonReport: Codable {
    let model: String
    let endpoint: String
    let prompt: String
    let rulePolicy: String
    let hybridMargin: Double
    let timing: String
    let order: String
    let startedAt: String
    var updatedAt: String
    let plannedCases: Int
    var status: String
    var error: String?
    var summaries: [String: ModeSummary]
    var results: [ComparisonRow]

    mutating func save(to url: URL) throws {
        updatedAt = ISO8601DateFormatter().string(from: Date())
        summaries = Dictionary(uniqueKeysWithValues: ["rules", "hybrid", "jev"].map {
            ($0, ModeSummary(rows: results, mode: $0))
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

enum Comparison {
    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }

    static func run(casesPath: String, lexiconPath: String, outputPath: String, apiKey: String) async throws {
        let cases = try JSONDecoder().decode([ComparisonCase].self, from: Data(contentsOf: URL(fileURLWithPath: casesPath)))
        guard !cases.isEmpty else { throw ComparisonError("No comparison cases selected.") }
        let prepared = try cases.map { test -> (ComparisonCase, [Candidate]) in
            let candidates = try CandidateBuilder.candidates(for: test.raw, includeSplits: true)
            let texts = Set(candidates.map(\.text))
            guard !test.acceptable.isEmpty, Set(test.acceptable + test.plausible).isSubset(of: texts) else {
                throw ComparisonError("Case \(test.id): acceptable/plausible text is absent from generated candidates.")
            }
            return (test, candidates)
        }
        let lexicon = try JSONDecoder().decode(RuleLexicon.self, from: Data(contentsOf: URL(fileURLWithPath: lexiconPath)))
        let rules = RuleSelector(lexicon: lexicon)
        let client = JevClient()
        let clock = ContinuousClock()
        let date = ISO8601DateFormatter().string(from: Date())
        let output = URL(fileURLWithPath: outputPath)
        var report = ComparisonReport(
            model: JevClient.model, endpoint: JevClient.endpoint, prompt: JevClient.instructions,
            rulePolicy: "External wordfreq 3.1.1 small en/ko Zipf dictionary; Latin exact lookup, Korean dictionary segmentation; character-weighted Zipf minus 0.5 per additional token boundary; last 40 letters script context prior <= 1.0. No evaluation labels in rule input.",
            hybridMargin: RuleSelector.hybridMargin,
            timing: "Each mode independently regenerates the same candidates and measures generation through completed decision, including JSON encode/decode for Jev. Excludes process start, dictionary loading, credentials, report writing, and IME UI. API round-trip time is also recorded separately.",
            order: "Rules first; hybrid/jev order alternates per case. Independent real HTTP requests, no answer reuse, no automatic retry or error replacement.",
            startedAt: date, updatedAt: date, plannedCases: cases.count,
            status: "running", error: nil, summaries: [:], results: [])
        try report.save(to: output)
        print("Comparison report: \(output.path)")
        for (index, item) in prepared.enumerated() {
            let (test, candidates) = item
            report.results.append(ComparisonRow(test: test, candidates: candidates, modes: [:]))
            let order = index.isMultiple(of: 2) ? ["rules", "hybrid", "jev"] : ["rules", "jev", "hybrid"]
            for mode in order {
                do {
                    let start = clock.now
                    let modeCandidates = try CandidateBuilder.candidates(for: test.raw, includeSplits: true)
                    var local: RuleDecision?
                    var remote: JevDecision?
                    if mode != "jev" {
                        local = rules.select(candidates: modeCandidates, before: test.before)
                    }
                    if mode == "jev" || (mode == "hybrid" && local!.margin < RuleSelector.hybridMargin) {
                        remote = try await client.decide(raw: test.raw, before: test.before,
                                                        candidates: modeCandidates, apiKey: apiKey)
                    }
                    let predicted = remote?.predicted ?? local!.predicted
                    let result = ModeResult(
                        predicted: predicted, correct: test.acceptable.contains(predicted),
                        route: remote == nil ? "rules" : "jev",
                        latencyMilliseconds: milliseconds(start.duration(to: clock.now)),
                        apiLatencyMilliseconds: remote?.latencyMilliseconds, rule: local,
                        answer: remote?.response.answers["interpretation"], usage: remote?.response.usage)
                    report.results[index].modes[mode] = result
                    try report.save(to: output)
                } catch {
                    report.status = "failed"
                    report.error = "Case \(test.id), mode \(mode): \(error.localizedDescription)"
                    try report.save(to: output)
                    throw ComparisonError("\(report.error!)\nCompleted results preserved: \(output.path)")
                }
            }
            let choices = ["rules", "hybrid", "jev"].map { mode in
                let result = report.results[index].modes[mode]!
                return "\(mode)=\(result.predicted) [\(result.correct ? "OK" : "WRONG"), \(result.route), \(String(format: "%.1f", result.latencyMilliseconds))ms]"
            }.joined(separator: " | ")
            print("\(index + 1)/\(prepared.count) \(test.id) \(choices)")
            fflush(stdout)
        }
        report.status = "completed"
        try report.save(to: output)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report.summaries), as: UTF8.self))
    }
}

private struct ComparisonError: LocalizedError {
    let detail: String
    init(_ detail: String) { self.detail = detail }
    var errorDescription: String? { detail }
}
