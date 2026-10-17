import Foundation

public struct RuleLexicon: Codable, Sendable {
    public let english: [String: Double]
    public let korean: [String: Double]

    public init(english: [String: Double], korean: [String: Double]) {
        self.english = english
        self.korean = korean
    }
}

public struct RuleScore: Codable, Sendable {
    public let id: String
    public let text: String
    public let score: Double
    public let lexical: Double
    public let contextPrior: Double
}

public struct RuleDecision: Codable, Sendable {
    public let choice: String
    public let predicted: String
    public let score: Double
    /// Difference between the highest and second-highest scores, not a probability.
    public let margin: Double
    public let ranking: [RuleScore]
}

/// A frozen dictionary-frequency baseline, not a port of Meltype's classifier.
/// Both English and Korean lexicons contain external wordfreq small-list Zipf scores.
public struct RuleSelector: Sendable {
    public static let hybridMargin = 1.5
    public static let boundaryPenalty = 0.5
    public static let contextLetterLimit = 40

    private let lexicon: RuleLexicon

    public init(lexicon: RuleLexicon) {
        self.lexicon = lexicon
    }

    /// The caller supplies a nonempty candidate list. Candidate IDs and split metadata
    /// are not scoring features, and equal scores retain the original candidate order.
    public func select(candidates: [Candidate], before: String) -> RuleDecision {
        let contextScripts = before.compactMap { character -> Script? in
            let script = Self.script(of: character)
            return script == .other ? nil : script
        }.suffix(Self.contextLetterLimit)
        let contextKorean = contextScripts.isEmpty ? nil
            : Double(contextScripts.filter { $0 == .korean }.count) / Double(contextScripts.count)
        let scored = candidates.enumerated().map { index, candidate in
            let characters = Array(candidate.text)
            let runs = Self.runs(characters)
            let length = characters.count
            let weighted = runs.reduce(0.0) { sum, run in
                switch run.script {
                case .english:
                    return sum + Double(run.text.count) * (lexicon.english[String(run.text).lowercased()] ?? 0)
                case .korean:
                    return sum + koreanEvidence(run.text, candidateLength: length)
                case .other:
                    return sum
                }
            }
            let lexical = length == 0 ? 0
                : weighted / Double(length) - Self.boundaryPenalty * Double(max(0, runs.count - 1))
            let relevant = characters.map(Self.script).filter { $0 != .other }
            let korean = relevant.isEmpty ? 0
                : Double(relevant.filter { $0 == .korean }.count) / Double(relevant.count)
            let prior = contextKorean.map { context in
                context * korean + (1 - context) * (1 - korean)
            } ?? 0
            return (index, RuleScore(id: candidate.id, text: candidate.text,
                                     score: lexical + prior, lexical: lexical, contextPrior: prior))
        }
        let ranking = scored.sorted {
            $0.1.score == $1.1.score ? $0.0 < $1.0 : $0.1.score > $1.1.score
        }.map(\.1)
        let winner = ranking[0]
        let margin = ranking.count > 1 ? winner.score - ranking[1].score : 0
        return RuleDecision(choice: winner.id, predicted: winner.text, score: winner.score,
                            margin: margin, ranking: ranking)
    }

    /// Maximize character-weighted frequency minus the fixed cost of inferred boundaries.
    /// Unknown spans have Zipf 0 and may remain one token instead of being split into letters.
    private func koreanEvidence(_ text: [Character], candidateLength: Int) -> Double {
        var best = [Double](repeating: -.infinity, count: text.count + 1)
        best[0] = 0
        for end in 1...text.count {
            for start in 0..<end {
                let word = String(text[start..<end])
                let frequency = lexicon.korean[word] ?? 0
                let boundary = start == 0 ? 0 : Self.boundaryPenalty * Double(candidateLength)
                let score = best[start] + Double(end - start) * frequency - boundary
                best[end] = max(best[end], score)
            }
        }
        return best[text.count]
    }

    private enum Script {
        case english, korean, other
    }

    private struct Run {
        let script: Script
        var text: [Character]
    }

    private static func script(of character: Character) -> Script {
        guard character.unicodeScalars.count == 1, let value = character.unicodeScalars.first?.value else {
            return .other
        }
        if (65...90).contains(value) || (97...122).contains(value) { return .english }
        if (0xAC00...0xD7A3).contains(value) { return .korean }
        // Unfinished jamo are absent from the syllable-only lexicon and remain OOV.
        return .other
    }

    private static func runs(_ characters: [Character]) -> [Run] {
        var runs: [Run] = []
        for character in characters {
            let script = script(of: character)
            if runs.last?.script == script {
                runs[runs.count - 1].text.append(character)
            } else {
                runs.append(Run(script: script, text: [character]))
            }
        }
        return runs
    }
}
