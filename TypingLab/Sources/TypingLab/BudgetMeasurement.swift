import AppKit
import TypingLabCore

/// Measures the real NSTextInputClient callbacks, after events traverse the installed IMK input method.
@MainActor
final class MeasuredTextView: NSTextView {
    struct Key: Codable {
        let id: Int64
        let character: String
        let posted: Double
        var receiveCount = 0
        var received: Double?
        var textApplied: Double?
    }
    struct Boundary: Codable {
        let keyID: Int64
        let posted: Double
        var committed: Double?
    }
    var measuring = false
    var keys: [Key] = []
    var boundaries: [Boundary] = []
    private var activeKey: Int?
    private var pendingBoundaries: [Int] = []
    private var alphabeticWord = false
    var lastTextApplication = 0.0

    func resetMeasurements() {
        keys.removeAll(); boundaries.removeAll(); pendingBoundaries.removeAll()
        activeKey = nil; alphabeticWord = false
    }
    func posted(_ stroke: KeyStroke) -> Int64 {
        let id = Int64(keys.count + 1)
        keys.append(Key(id: id, character: stroke.character, posted: ProcessInfo.processInfo.systemUptime))
        return id
    }
    override func keyDown(with event: NSEvent) {
        if measuring {
            let id = event.cgEvent!.getIntegerValueField(.eventSourceUserData)
            precondition(id > 0 && id <= keys.count, "Measured event lost its identity")
            let index = Int(id - 1)
            keys[index].receiveCount += 1
            keys[index].received = ProcessInfo.processInfo.systemUptime
            activeKey = index
            let character = keys[index].character
            if character.allSatisfy({ $0.isASCII && $0.isLetter }) {
                alphabeticWord = true
            } else if alphabeticWord {
                boundaries.append(Boundary(keyID: id, posted: keys[index].posted))
                pendingBoundaries.append(boundaries.count - 1)
                alphabeticWord = false
            }
        }
        super.keyDown(with: event)
        activeKey = nil
    }
    private func appliedText() {
        lastTextApplication = ProcessInfo.processInfo.systemUptime
        if measuring, let index = activeKey, keys[index].textApplied == nil {
            keys[index].textApplied = lastTextApplication
        }
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        appliedText()
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        appliedText()
        let text = (string as? NSAttributedString)?.string ?? (string as! String)
        if measuring, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !pendingBoundaries.isEmpty {
            let index = pendingBoundaries.removeFirst()
            boundaries[index].committed = ProcessInfo.processInfo.systemUptime
        }
    }
    var pendingWordCount: Int { pendingBoundaries.count }
}

@MainActor
extension LabModel {
    private struct BudgetConfiguration: Decodable {
        struct Case: Decodable { let input: String; let expected: String }
        let output: String
        let durationSeconds: Double
        let intervalMilliseconds: Double
        let cases: [Case]
    }
    func measureBudget(configuration url: URL) async throws {
        let config = try JSONDecoder().decode(BudgetConfiguration.self, from: Data(contentsOf: url))
        guard let editor = editor as? MeasuredTextView else { preconditionFailure("Measured editor missing") }
        precondition(config.durationSeconds > 0 && config.intervalMilliseconds > 0 && !config.cases.isEmpty)
        guard CGPreflightPostEventAccess() else { throw TypingError.permissionRequired }
        sourceID = "com.yeop.inputmethod.Hannyeong"
        try selectSource()
        // Switching/restarting an installed input source establishes its IMK connection asynchronously.
        try await Task.sleep(for: .seconds(1))
        // A source change was observed to bring System Settings forward before the first key.
        // Establish the test window again before starting the timed input interval.
        editor.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let focusDeadline = ProcessInfo.processInfo.systemUptime + 10
        while !NSApp.isActive || editor.window?.isKeyWindow != true {
            guard ProcessInfo.processInfo.systemUptime < focusDeadline else {
                throw NSError(domain: "TypingLab.Budget", code: 1, userInfo:
                    [NSLocalizedDescriptionKey: "Could not establish the test foreground after source selection"])
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        editor.window?.makeFirstResponder(editor)
        editor.inputContext?.activate()
        let plan = try config.cases.map { (expected: $0.expected, strokes: try Keyboard.strokes(for: $0.input + " ")) }
        editor.resetMeasurements(); editor.measuring = true
        running = true; status = "CPU·메모리·입력 지연 측정 중"
        defer {
            editor.measuring = false; running = false
            do {
                let keys = try JSONSerialization.jsonObject(with: JSONEncoder().encode(editor.keys))
                let boundaries = try JSONSerialization.jsonObject(with: JSONEncoder().encode(editor.boundaries))
                let trace: [String: Any] = ["keys": keys, "boundaries": boundaries, "text": editor.string,
                    "hasMarkedText": editor.hasMarkedText(), "pendingWordCount": editor.pendingWordCount]
                try JSONSerialization.data(withJSONObject: trace).write(
                    to: URL(fileURLWithPath: config.output + ".trace.json"), options: .atomic)
            } catch { NSLog("Budget trace export failed: %@", String(describing: error)) }
        }
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + config.durationSeconds
        var rows: [[String: Any]] = []
        var sequence = 0
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard NSApp.isActive, editor.window?.isKeyWindow == true,
                  editor.window?.firstResponder === editor else {
                throw NSError(domain: "TypingLab.Budget", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Measurement lost focus: active=\(NSApp.isActive), keyWindow=\(editor.window?.isKeyWindow == true), responder=\(editor.window?.firstResponder === editor), foreground=\(String(describing: NSWorkspace.shared.frontmostApplication?.bundleIdentifier))"])
            }
            let currentSource = try InputSources.current()
            guard currentSource == sourceID,
                  editor.inputContext?.selectedKeyboardInputSource == sourceID else {
                throw NSError(domain: "TypingLab.Budget", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "Input source changed: global=\(currentSource), client=\(String(describing: editor.inputContext?.selectedKeyboardInputSource))"])
            }
            let sentence = plan[sequence % plan.count]
            editor.string = ""; editor.setSelectedRange(NSRange(location: 0, length: 0))
            let start = ProcessInfo.processInfo.systemUptime
            for (index, stroke) in sentence.strokes.enumerated() {
                let target = start + Double(index) * config.intervalMilliseconds / 1000
                let remaining = target - ProcessInfo.processInfo.systemUptime
                if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
                let id = editor.posted(stroke)
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: stroke.code, keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: stroke.code, keyDown: false) else {
                    throw TypingError.eventCreation
                }
                down.flags = stroke.shift ? .maskShift : []; up.flags = down.flags
                down.setIntegerValueField(.eventSourceUserData, value: id)
                up.setIntegerValueField(.eventSourceUserData, value: id)
                down.postToPid(ProcessInfo.processInfo.processIdentifier)
                up.postToPid(ProcessInfo.processInfo.processIdentifier)
            }
            let completionDeadline = ProcessInfo.processInfo.systemUptime + 30
            // IMK can deliver the separator after inserting the word. Reset only after text has settled.
            while editor.pendingWordCount > 0 || editor.hasMarkedText() || editor.keys.last?.received == nil ||
                    ProcessInfo.processInfo.systemUptime - editor.lastTextApplication < 0.1 {
                guard ProcessInfo.processInfo.systemUptime < completionDeadline else { throw TypingError.compositionTimeout }
                try await Task.sleep(for: .milliseconds(2))
            }
            let actual = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append(["sequence": sequence, "expected": sentence.expected, "actual": actual,
                         "passed": actual == sentence.expected, "keyCount": sentence.strokes.count,
                         "started": start, "finished": ProcessInfo.processInfo.systemUptime])
            sequence += 1
            status = "측정 중 · \(sequence)문장 · \(editor.keys.count)키"
            let progress: [String: Any] = ["started": started, "now": ProcessInfo.processInfo.systemUptime,
                "sentences": sequence, "keys": editor.keys.count, "correct": rows.filter { $0["passed"] as! Bool }.count]
            try JSONSerialization.data(withJSONObject: progress).write(
                to: URL(fileURLWithPath: config.output + ".progress.json"), options: .atomic)
        }
        let keyData = try JSONSerialization.jsonObject(with: JSONEncoder().encode(editor.keys))
        let boundaryData = try JSONSerialization.jsonObject(with: JSONEncoder().encode(editor.boundaries))
        let result: [String: Any] = ["inputSourceID": sourceID, "route": "CGEventPostToPid-installed-IMK",
            "latencyEndpoint": "NSTextView text applied; display refresh is not measured",
            "intervalMilliseconds": config.intervalMilliseconds, "started": started,
            "finished": ProcessInfo.processInfo.systemUptime, "results": rows, "keys": keyData, "boundaries": boundaryData]
        try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(
            to: URL(fileURLWithPath: config.output), options: .atomic)
        status = "측정 완료 · \(sequence)문장"
    }
}
