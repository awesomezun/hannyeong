import Foundation
import Darwin

public struct LocalRuntimeConfiguration: Codable, Sendable {
    public let python: String
    public let worker: String
    public let model: String

    public init(python: String, worker: String, model: String) {
        self.python = python
        self.worker = worker
        self.model = model
    }
}

public struct LocalDecision: Codable, Sendable {
    public let predicted: String
    public let probabilities: [String: Double]
    public let personalRevision: Int
}

public struct LocalUpdate: Codable, Sendable {
    public let personalRevision: Int
    public let beforeProbability: Double
    public let afterProbability: Double
}

public struct LocalModelInfo: Codable, Sendable {
    public let modelID: String
}

public struct LocalRemoval: Codable, Sendable {
    public let personalRevision: Int
    public let removedCount: Int
}

public struct LocalScopeUpdate: Codable, Sendable {
    public let personalRevision: Int
}

public struct LocalDecisionError: LocalizedError {
    public let detail: String
    public init(detail: String) { self.detail = detail }
    public var errorDescription: String? { detail }
}

/// A single persistent Python model process. All pipe I/O runs on its own queue,
/// leaving the input method's main thread free while loading or scoring the model.
public final class LocalDecisionClient: @unchecked Sendable {
    private let runtime: LocalRuntimeConfiguration
    private let personalURL: URL
    private let queue = DispatchQueue(label: "com.yeop.Hannyeong.LocalDecision")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var diagnostics: FileHandle?
    private var readBuffer = [UInt8](repeating: 0, count: 4096)

    public init(runtime: LocalRuntimeConfiguration, personalURL: URL) {
        self.runtime = runtime
        self.personalURL = personalURL
    }

    public func prepare() async throws -> LocalModelInfo {
        try await request(operation: "prepare", raw: "", before: "", candidates: [], preferred: nil)
    }

    deinit {
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
        try? output?.close()
        try? diagnostics?.close()
    }

    public func decide(raw: String, before: String, candidates: [Candidate]) async throws -> LocalDecision {
        let result: LocalDecision = try await request(operation: "decide", raw: raw, before: before,
                                                      candidates: candidates, preferred: nil)
        guard candidates.count >= 2,
              candidates.contains(where: { $0.text == result.predicted }),
              Set(result.probabilities.keys) == Set(candidates.map(\.id)),
              result.probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              abs(result.probabilities.values.reduce(0, +) - 1) < 0.0001 else {
            throw LocalDecisionError(detail: "Local model returned an invalid candidate distribution")
        }
        return result
    }

    public func correct(raw: String, before: String, candidates: [Candidate], preferred: String,
                        scope: CorrectionScope = .context) async throws -> LocalUpdate {
        try await request(operation: "correct", raw: raw, before: before,
                          candidates: candidates, preferred: preferred, scope: scope)
    }

    public func forget(raw: String, before: String, preferred: String,
                       scope: CorrectionScope) async throws -> LocalRemoval {
        try await request(operation: "forget", raw: raw, before: before,
                          candidates: [], preferred: preferred, scope: scope)
    }

    public func forget(_ entries: [CorrectionExample]) async throws -> LocalRemoval {
        try await request(operation: "forget_many", raw: "", before: "",
                          candidates: [], preferred: nil, corrections: entries)
    }

    public func changeScope(of entry: CorrectionExample, to scope: CorrectionScope) async throws -> LocalScopeUpdate {
        try await request(operation: "change_scope", raw: "", before: "", candidates: [],
                          preferred: nil, scope: scope, corrections: [entry])
    }

    private struct Request: Encodable {
        let operation: String
        let raw: String
        let before: String
        let candidates: [Candidate]
        let preferred: String?
        let scope: String?
        let corrections: [CorrectionExample]?
    }

    private struct Response<T: Decodable>: Decodable {
        let result: T?
        let error: String?
    }

    private func request<T: Decodable & Sendable>(operation: String, raw: String, before: String,
                                                 candidates: [Candidate], preferred: String?,
                                                 scope: CorrectionScope? = nil,
                                                 corrections: [CorrectionExample]? = nil) async throws -> T {
        let data = try JSONEncoder().encode(Request(operation: operation, raw: raw,
                                                   before: before, candidates: candidates, preferred: preferred,
                                                   scope: scope?.rawValue, corrections: corrections))
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if process == nil { try launch() }
                    guard let process, process.isRunning, let input, let output else {
                        throw LocalDecisionError(detail: "Local decision worker is not running")
                    }
                    try input.write(contentsOf: data + Data([10]))
                    var line = Data()
                    // The serial queue sends one request and receives one newline-terminated reply.
                    while line.last != 10 {
                        let count = readBuffer.withUnsafeMutableBytes {
                            Darwin.read(output.fileDescriptor, $0.baseAddress, $0.count)
                        }
                        guard count > 0 else {
                            let detail = count == 0
                                ? "Local decision worker closed stdout. See local-model.log."
                                : "Local decision worker stdout read failed: \(String(cString: strerror(errno)))"
                            throw LocalDecisionError(detail: detail)
                        }
                        readBuffer.withUnsafeBytes {
                            line.append($0.bindMemory(to: UInt8.self).baseAddress!, count: count)
                        }
                    }
                    line.removeLast()
                    let response = try JSONDecoder().decode(Response<T>.self, from: line)
                    if let error = response.error { throw LocalDecisionError(detail: error) }
                    guard let result = response.result else {
                        throw LocalDecisionError(detail: "Local worker returned no result")
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func launch() throws {
        let directory = personalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let log = directory.appendingPathComponent("local-model.log")
        if !FileManager.default.fileExists(atPath: log.path) {
            guard FileManager.default.createFile(atPath: log.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw LocalDecisionError(detail: "Could not create local model diagnostics")
            }
        }
        diagnostics = try FileHandle(forWritingTo: log)
        try diagnostics?.seekToEnd()
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = URL(fileURLWithPath: runtime.python)
        // Bytecode files inside the signed app bundle invalidate its resource seal.
        // -E -s: ignore PYTHON* variables and user site-packages so only the configured runtime is used.
        child.arguments = ["-B", "-E", "-s", runtime.worker, "--model", runtime.model, "--personal", personalURL.path]
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = diagnostics
        try child.run()
        process = child
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
    }
}
