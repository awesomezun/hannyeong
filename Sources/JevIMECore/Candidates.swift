import CLibHangul
import Foundation

public enum CompositionError: Error, LocalizedError {
    case emptyWord
    case invalidKey(String)
    case contextUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyWord: return "An input word is required."
        case .invalidKey(let key): return "Unsupported two-set key: \(key)"
        case .contextUnavailable: return "libhangul could not create a two-set input context."
        }
    }
}

public enum HangulComposer {
    /// Copy completed syllables locally; the caller decides when to commit to an app.
    public static func compose(_ raw: String) throws -> String {
        guard let context = hangul_ic_new("2") else { throw CompositionError.contextUnavailable }
        defer { hangul_ic_delete(context) }
        var text = ""
        for scalar in raw.unicodeScalars {
            guard (65...90).contains(scalar.value) || (97...122).contains(scalar.value),
                  hangul_ic_process(context, Int32(scalar.value)) else {
                throw CompositionError.invalidKey(String(scalar))
            }
            text += copyString(hangul_ic_get_commit_string(context))
        }
        text += copyString(hangul_ic_flush(context))
        return text
    }

    private static func copyString(_ pointer: UnsafePointer<UInt32>) -> String {
        var text = ""
        var current = pointer
        while current.pointee != 0 {
            text.unicodeScalars.append(UnicodeScalar(current.pointee)!)
            current += 1
        }
        return text
    }
}

public struct Candidate: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let splitIndex: Int?

    public init(id: String, text: String, splitIndex: Int? = nil) {
        self.id = id
        self.text = text
        self.splitIndex = splitIndex
    }
}

public enum CandidateBuilder {
    /// Generate interpretations mechanically, without dictionaries or language scores.
    public static func candidates(for raw: String, includeSplits: Bool) throws -> [Candidate] {
        guard !raw.isEmpty else { throw CompositionError.emptyWord }
        let korean = try HangulComposer.compose(raw)
        var readings: [(String, Int?)] = [(raw, nil), (korean, nil)]
        if includeSplits {
            for index in 1..<raw.count {
                let suffix = try HangulComposer.compose(String(raw.dropFirst(index)))
                readings.append((String(raw.prefix(index)) + suffix, index))
            }
        }
        var seen = Set<String>()
        var candidates: [Candidate] = []
        for (text, index) in readings where seen.insert(text).inserted {
            candidates.append(Candidate(id: "c\(candidates.count)", text: text, splitIndex: index))
        }
        return candidates
    }
}
