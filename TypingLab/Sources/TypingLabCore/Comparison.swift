import Foundation

public struct DiffPiece: Equatable {
    public let text: String
    public let changed: Bool
}

public enum Comparison {
    public static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func matches(_ expected: String, _ actual: String) -> Bool {
        normalized(expected) == normalized(actual)
    }
    public static func differences(_ expected: String, _ actual: String) -> (expected: [DiffPiece], actual: [DiffPiece]) {
        let before = Array(normalized(expected)), after = Array(normalized(actual))
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in after.difference(from: before) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        func pieces(_ letters: [Character], _ changes: Set<Int>) -> [DiffPiece] {
            var output = [DiffPiece]()
            for (index, letter) in letters.enumerated() {
                let changed = changes.contains(index)
                if let last = output.last, last.changed == changed {
                    output[output.count - 1] = DiffPiece(text: last.text + String(letter), changed: changed)
                } else { output.append(DiffPiece(text: String(letter), changed: changed)) }
            }
            return output
        }
        return (pieces(before, removed), pieces(after, inserted))
    }
}

public struct TestResult: Codable, Identifiable {
    public let id: UUID
    public let iteration: Int
    public let sentenceNumber: Int
    public let expected: String
    public let actual: String
    public let inputSourceID: String
    public let inputSourceName: String
    public let keyCount: Int
    public let elapsedMilliseconds: Int
    public let passed: Bool

    public init(iteration: Int, sentenceNumber: Int, expected: String, actual: String,
                inputSourceID: String, inputSourceName: String, keyCount: Int, elapsedMilliseconds: Int) {
        id = UUID(); self.iteration = iteration; self.sentenceNumber = sentenceNumber
        self.expected = expected; self.actual = actual; self.inputSourceID = inputSourceID
        self.inputSourceName = inputSourceName; self.keyCount = keyCount
        self.elapsedMilliseconds = elapsedMilliseconds; passed = Comparison.matches(expected, actual)
    }
}
