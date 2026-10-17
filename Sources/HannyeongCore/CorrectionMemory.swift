import Foundation

public enum CorrectionScope: String, Codable, Sendable {
    case context, always
}

public struct CorrectionExample: Codable, Equatable, Sendable {
    public let raw: String
    public let before: String
    public let rejected: String
    public let preferred: String
    public let scope: CorrectionScope

    public init(raw: String, before: String, rejected: String, preferred: String, scope: CorrectionScope) {
        self.raw = raw
        self.before = before
        self.rejected = rejected
        self.preferred = preferred
        self.scope = scope
    }
}

public enum CorrectionMemoryError: LocalizedError {
    case invalidPreferred(String)
    case missingRecord

    public var errorDescription: String? {
        switch self {
        case .invalidPreferred(let preferred):
            return "The preferred text is not an input candidate: \(preferred)"
        case .missingRecord:
            return "The selected correction no longer exists"
        }
    }
}

public struct CorrectionMemory: Codable, Sendable {
    public private(set) var entries: [CorrectionExample] = []

    public init() {}

    public mutating func record(raw: String, before: String, rejected: String,
                                preferred: String, scope: CorrectionScope) throws {
        let candidates = try CandidateBuilder.candidates(for: raw, includeSplits: true)
        guard candidates.contains(where: { $0.text == preferred }) else {
            throw CorrectionMemoryError.invalidPreferred(preferred)
        }
        let context = Self.normalized(before)
        entries.removeAll {
            $0.raw == raw && ($0.scope == .always || ($0.before == context && $0.scope == scope))
        }
        entries.append(CorrectionExample(raw: raw, before: context, rejected: rejected,
                                         preferred: preferred, scope: scope))
    }

    public func preferred(raw: String, before: String) -> String? {
        if let global = entries.last(where: { $0.raw == raw && $0.scope == .always }) {
            return global.preferred
        }
        let context = Self.normalized(before)
        return entries.last(where: { $0.raw == raw && $0.scope == .context && $0.before == context })?.preferred
    }

    public mutating func remove(_ entry: CorrectionExample) throws {
        try remove([entry])
    }

    @discardableResult
    public mutating func changeScope(of entry: CorrectionExample, to scope: CorrectionScope) throws -> CorrectionExample {
        guard let index = entries.firstIndex(of: entry) else { throw CorrectionMemoryError.missingRecord }
        let updated = CorrectionExample(raw: entry.raw, before: entry.before, rejected: entry.rejected,
                                        preferred: entry.preferred, scope: scope)
        entries[index] = updated
        return updated
    }

    public mutating func remove(_ selected: [CorrectionExample]) throws {
        guard selected.allSatisfy({ entries.contains($0) }) else {
            throw CorrectionMemoryError.missingRecord
        }
        entries.removeAll { selected.contains($0) }
    }

    public func examples(for raw: String) -> [CorrectionExample] {
        Array(entries.filter { $0.raw == raw && $0.scope == .context }.suffix(3).reversed())
    }

    private static func normalized(_ before: String) -> String {
        String(before.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines).suffix(120))
    }
}
