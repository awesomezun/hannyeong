import Foundation
import HannyeongCore

private struct CLIError: LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}

private struct EvaluationCase: Codable {
    let id: String
    let category: String
    let before: String
    let raw: String
    let expected: String
    let split: Bool
    let partition: String
}

private struct CaseResult: Codable {
    let test: EvaluationCase
    let candidates: [Candidate]
    let predicted: String
    let correct: Bool
    let latencyMilliseconds: Double
    let answer: JevAnswer
    let usage: JevUsage
}

private struct Accuracy: Codable {
    let completed: Int
    let correct: Int
    let accuracy: Double?
}

private struct Summary: Codable {
    let completed: Int
    let correct: Int
    let accuracy: Double?
    let categories: [String: Accuracy]
    let p50Milliseconds: Double?
    let p95Milliseconds: Double?
    let maxMilliseconds: Double?

    init(_ results: [CaseResult]) {
        completed = results.count
        correct = results.filter(\.correct).count
        accuracy = completed == 0 ? nil : Double(correct) / Double(completed)
        categories = Dictionary(grouping: results, by: { $0.test.category }).mapValues { group in
            let correct = group.filter(\.correct).count
            return Accuracy(completed: group.count, correct: correct, accuracy: Double(correct) / Double(group.count))
        }
        let times = results.map(\.latencyMilliseconds).sorted()
        func percentile(_ fraction: Double) -> Double? {
            guard !times.isEmpty else { return nil }
            return times[max(0, Int(ceil(Double(times.count) * fraction)) - 1)]
        }
        p50Milliseconds = percentile(0.5)
        p95Milliseconds = percentile(0.95)
        maxMilliseconds = times.last
    }
}

private struct EvaluationReport: Codable {
    let model: String
    let endpoint: String
    let prompt: String
    let startedAt: String
    var updatedAt: String
    let partition: String
    let planned: Int
    var status: String
    var error: String?
    var summary: Summary
    var results: [CaseResult]

    mutating func save(to url: URL) throws {
        updatedAt = ISO8601DateFormatter().string(from: Date())
        summary = Summary(results)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CLI.json(self, pretty: true).write(to: url, options: .atomic)
    }
}

private enum CLI {
    static let usage = """
        Usage:
          hannyeong-eval candidates <raw> [--split]
          hannyeong-eval decide <raw> [--before <context>] [--split] [--env-key]
          hannyeong-eval evaluate <cases.json> [--partition development|holdout|all] [--output <path>] [--env-key]
          hannyeong-eval compare <cases.json> --lexicon <path> --output <path> [--env-key]
          hannyeong-eval local <raw> --runtime <path> --personal <path> [--before <context>]
          hannyeong-eval local-correct <raw> --runtime <path> --personal <path> --preferred <text> [--before <context>]

        By default, decide/evaluate read the existing OnText TypeSafe key from macOS Keychain.
        --env-key explicitly reads TYPESAFE_API_KEY instead.
        Evaluate writes an incremental report in reports/ unless --output is supplied.
        """

    static func json<T: Encodable>(_ value: T, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func printJSON<T: Encodable>(_ value: T) throws {
        print(String(decoding: try json(value, pretty: true), as: UTF8.self))
    }

    static func credential(fromEnvironment: Bool) throws -> String {
        if fromEnvironment {
            guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else {
                throw CLIError(detail: "--env-key requires TYPESAFE_API_KEY.")
            }
            return key
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "com.yeop.OnText.SmartPaste.TypeSafe", "-a", "typesafe-api-key", "-w"]
        let output = Pipe(), errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errorOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw CLIError(detail: "Keychain error: \(detail)")
        }
        guard let value = String(data: data, encoding: .utf8), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError(detail: "The TypeSafe Keychain item contains no UTF-8 key.")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func run() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty, args[0] != "--help", args[0] != "-h" else {
            print(usage)
            return
        }
        let command = args.removeFirst()
        guard !args.isEmpty else { throw CLIError(detail: usage) }
        let input = args.removeFirst()
        var values: [String: String] = [:]
        var flags = Set<String>()
        while !args.isEmpty {
            let option = args.removeFirst()
            switch option {
            case "--split", "--env-key": flags.insert(option)
            case "--before", "--partition", "--output", "--lexicon", "--runtime", "--personal", "--preferred":
                guard !args.isEmpty else { throw CLIError(detail: "\(option) needs a value.") }
                values[option] = args.removeFirst()
            default: throw CLIError(detail: "Unknown option: \(option)\n\(usage)")
            }
        }
        let allowed: Set<String>
        switch command {
        case "candidates": allowed = ["--split"]
        case "decide": allowed = ["--before", "--split", "--env-key"]
        case "evaluate": allowed = ["--partition", "--output", "--env-key"]
        case "compare": allowed = ["--lexicon", "--output", "--env-key"]
        case "local": allowed = ["--before", "--runtime", "--personal"]
        case "local-correct": allowed = ["--before", "--runtime", "--personal", "--preferred"]
        default: throw CLIError(detail: "Unknown command: \(command)\n\(usage)")
        }
        guard flags.union(values.keys).isSubset(of: allowed) else {
            throw CLIError(detail: "Unsupported option for \(command).\n\(usage)")
        }
        if command == "candidates" {
            try printJSON(CandidateBuilder.candidates(for: input, includeSplits: flags.contains("--split")))
            return
        }
        if command == "local" || command == "local-correct" {
            guard let runtimePath = values["--runtime"], let personalPath = values["--personal"] else {
                throw CLIError(detail: "local requires --runtime and --personal")
            }
            let runtime = try JSONDecoder().decode(LocalRuntimeConfiguration.self,
                from: Data(contentsOf: URL(fileURLWithPath: runtimePath)))
            let client = LocalDecisionClient(runtime: runtime, personalURL: URL(fileURLWithPath: personalPath))
            let candidates = try CandidateBuilder.candidates(for: input, includeSplits: true)
            if command == "local-correct" {
                guard let preferred = values["--preferred"] else {
                    throw CLIError(detail: "local-correct requires --preferred")
                }
                try printJSON(await client.correct(raw: input, before: values["--before"] ?? "",
                                                   candidates: candidates, preferred: preferred))
            } else {
                try printJSON(await client.decide(raw: input, before: values["--before"] ?? "", candidates: candidates))
            }
            return
        }
        let key = try credential(fromEnvironment: flags.contains("--env-key"))
        if command == "compare" {
            guard let lexiconPath = values["--lexicon"], let outputPath = values["--output"] else {
                throw CLIError(detail: "compare requires --lexicon and --output.")
            }
            try await Comparison.run(casesPath: input, lexiconPath: lexiconPath, outputPath: outputPath, apiKey: key)
            return
        }
        let client = JevClient()
        if command == "decide" {
            let candidates = try CandidateBuilder.candidates(for: input, includeSplits: flags.contains("--split"))
            try printJSON(await client.decide(raw: input, before: values["--before"] ?? "", candidates: candidates, apiKey: key))
            return
        }
        let partition = values["--partition"] ?? "all"
        guard ["development", "holdout", "all"].contains(partition) else {
            throw CLIError(detail: "Partition must be development, holdout, or all.")
        }
        let cases = try JSONDecoder().decode([EvaluationCase].self, from: Data(contentsOf: URL(fileURLWithPath: input)))
            .filter { partition == "all" || $0.partition == partition }
        guard !cases.isEmpty else { throw CLIError(detail: "No cases selected for \(partition).") }
        let prepared = try cases.map { test -> (EvaluationCase, [Candidate]) in
            let candidates = try CandidateBuilder.candidates(for: test.raw, includeSplits: test.split)
            guard candidates.contains(where: { $0.text == test.expected }) else {
                throw CLIError(detail: "Case \(test.id): expected text is absent from generated candidates.")
            }
            return (test, candidates)
        }
        let date = ISO8601DateFormatter().string(from: Date())
        let defaultPath = "reports/eval-\(date.replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString.prefix(8)).json"
        let output = URL(fileURLWithPath: values["--output"] ?? defaultPath)
        var report = EvaluationReport(model: JevClient.model, endpoint: JevClient.endpoint, prompt: JevClient.instructions,
                                      startedAt: date, updatedAt: date, partition: partition, planned: prepared.count,
                                      status: "running", error: nil, summary: Summary([]), results: [])
        try report.save(to: output)
        print("Report: \(output.path)")
        for (test, candidates) in prepared {
            do {
                let decision = try await client.decide(raw: test.raw, before: test.before, candidates: candidates, apiKey: key)
                let result = CaseResult(test: test, candidates: candidates, predicted: decision.predicted,
                                        correct: decision.predicted == test.expected, latencyMilliseconds: decision.latencyMilliseconds,
                                        answer: decision.response.answers["interpretation"]!, usage: decision.response.usage)
                report.results.append(result)
                try report.save(to: output)
                let expectation = String(decoding: try json(test.expected), as: UTF8.self)
                let prediction = String(decoding: try json(result.predicted), as: UTF8.self)
                print("\(report.results.count)/\(prepared.count) \(test.id) expected=\(expectation) predicted=\(prediction) correct=\(result.correct) latency_ms=\(String(format: "%.1f", result.latencyMilliseconds)) confidence=\(String(format: "%.4f", result.answer.confidence))")
                fflush(stdout)
            } catch {
                report.status = "failed"
                report.error = "Case \(test.id): \(error.localizedDescription)"
                try report.save(to: output)
                throw CLIError(detail: "\(report.error!)\nCompleted results preserved: \(output.path)")
            }
        }
        report.status = "completed"
        try report.save(to: output)
        try printJSON(report.summary)
    }
}

do {
    try await CLI.run()
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
