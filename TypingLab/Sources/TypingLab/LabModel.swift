import AppKit
import Carbon
import SwiftUI
import TypingLabCore

@MainActor
final class LabModel: ObservableObject {
    @Published var expectedText = ""
    @Published var sources = [InputSourceInfo]()
    @Published var sourceID = ""
    @Published var intervalMS = 35.0
    @Published var repeats = 1
    @Published var status = "문장을 붙여넣고 입력기를 선택한 다음 시작하세요."
    @Published var running = false
    @Published var paused = false
    @Published var hasPermission = false
    @Published var results = [TestResult]()
    @Published var progress = 0.0
    @Published var exportStatus = ""
    var editor: NSTextView?
    private var task: Task<Void, Never>?
    private var expectedSource = ""

    func load() {
        do {
            guard let url = Bundle.main.url(forResource: "default-sentences", withExtension: "txt") else {
                throw CocoaError(.fileNoSuchFile)
            }
            expectedText = try String(contentsOf: url, encoding: .utf8)
            sources = try InputSources.available()
            sourceID = try InputSources.current()
            refreshPermission()
        } catch { report(error) }
    }

    func refreshPermission() { hasPermission = CGPreflightPostEventAccess() }
    func requestPermission() {
        _ = CGRequestPostEventAccess()
        refreshPermission()
        if !hasPermission { status = "시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 TypingLab을 허용해 주세요." }
    }
    func selectSource() throws {
        guard let editor, let context = editor.inputContext,
              let source = sources.first(where: { $0.id == sourceID }) else { throw TypingError.sourceUnavailable }
        editor.window?.makeFirstResponder(editor)
        guard TISSelectInputSource(source.source) == noErr else { throw TypingError.sourceUnavailable }
        context.selectedKeyboardInputSource = sourceID
    }

    func start() {
        guard !running, let editor else { return }
        do {
            NSApp.activate(ignoringOtherApps: true)
            editor.window?.makeKeyAndOrderFront(nil)
            refreshPermission()
            guard hasPermission else { throw TypingError.permissionRequired }
            let lines = expectedText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { throw TypingError.noText }
            let plans = try lines.map { try Keyboard.strokes(for: $0 + " ") }
            guard let source = sources.first(where: { $0.id == sourceID }) else { throw TypingError.sourceUnavailable }
            expectedSource = sourceID
            let count = repeats, speed = intervalMS, selectedID = sourceID, selectedName = source.name
            results = []; progress = 0; exportStatus = ""; running = true; paused = false
            let totalKeys = plans.reduce(0) { $0 + $1.count } * count
            task = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(100))
                    try selectSource()
                    try await Task.sleep(for: .milliseconds(100))
                    var completedKeys = 0
                    for iteration in 1...count {
                        for (index, line) in lines.enumerated() {
                            try await ready()
                            editor.inputContext?.discardMarkedText()
                            editor.unmarkText()
                            editor.setSelectedRange(NSRange(location: 0, length: 0))
                            editor.string = ""; editor.setSelectedRange(NSRange(location: 0, length: 0))
                            try await Task.sleep(for: .milliseconds(100))
                            let begin = Date()
                            for stroke in plans[index] {
                                try await ready()
                                status = "\(iteration)/\(count)회 · \(index + 1)/\(lines.count)문장 타이핑 중"
                                try post(stroke)
                                try await Task.sleep(for: .milliseconds(speed))
                                if " .,?!:;".contains(stroke.character) { try await waitForCommit() }
                                completedKeys += 1; progress = Double(completedKeys) / Double(totalKeys)
                            }
                            try await waitForCommit()
                            results.append(TestResult(iteration: iteration, sentenceNumber: index + 1,
                                                      expected: line, actual: editor.string,
                                                      inputSourceID: selectedID, inputSourceName: selectedName,
                                                      keyCount: plans[index].count,
                                                      elapsedMilliseconds: Int(Date().timeIntervalSince(begin) * 1000)))
                        }
                    }
                    running = false; paused = false
                    status = "완료 · \(results.count)건 중 \(results.filter(\.passed).count)건 일치"
                } catch is CancellationError {
                    running = false; paused = false; status = "중단했습니다. 완료된 결과는 저장할 수 있습니다."
                } catch { running = false; paused = false; report(error) }
            }
        } catch { report(error) }
    }

    private func ready() async throws {
        try Task.checkCancellation()
        while paused { try await Task.sleep(for: .milliseconds(50)); try Task.checkCancellation() }
        guard let editor, NSApp.isActive, editor.window?.isKeyWindow == true,
              editor.window?.firstResponder === editor else {
            NSLog("TypingLab paused: test window lost focus; foreground=%@",
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")
            paused = true; status = "앱을 앞으로 가져온 뒤 재개를 누르세요. 실제 입력기 테스트는 활성 창에서 진행합니다."
            try await ready(); return
        }
        guard try InputSources.current() == expectedSource,
              editor.inputContext?.selectedKeyboardInputSource == expectedSource else {
            NSLog("TypingLab input source changed: expected=%@ actual=%@", expectedSource,
                  String(describing: editor.inputContext?.selectedKeyboardInputSource))
            throw TypingError.sourceChanged
        }
    }

    private func post(_ stroke: KeyStroke) throws {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: stroke.code, keyDown: down) else {
                throw TypingError.eventCreation
            }
            event.flags = stroke.shift ? [.maskShift] : []
            event.setIntegerValueField(.eventSourceUserData, value: 0x545950454C4142)
            event.postToPid(ProcessInfo.processInfo.processIdentifier)
        }
    }

    private func waitForCommit() async throws {
        try await Task.sleep(for: .milliseconds(60))
        let deadline = Date().addingTimeInterval(30)
        while editor?.hasMarkedText() == true {
            try await ready()
            guard Date() < deadline else { throw TypingError.compositionTimeout }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func togglePause() {
        guard running else { return }
        if paused {
            NSApp.activate(ignoringOtherApps: true)
            editor?.window?.makeKeyAndOrderFront(nil)
            editor?.window?.makeFirstResponder(editor); paused = false
        }
        else { paused = true; status = "일시정지했습니다." }
    }
    func stop() { task?.cancel() }
    func report(_ error: Error) {
        NSLog("TypingLab error: %@", String(describing: error))
        status = (error as? LocalizedError)?.errorDescription ?? "작업을 완료하지 못했습니다. 문장과 앱 설정을 확인해 주세요."
    }

    func saveResults() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "TypingLab-results.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try save(to: url); exportStatus = "결과를 저장했습니다." } catch { report(error) }
    }
    func save(to url: URL) throws {
        struct Export: Encodable {
            let createdAt: Date
            let route: String
            let keyboard: String
            let intervalMilliseconds: Double
            let results: [TestResult]
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Export(createdAt: Date(), route: "CGEventPostToPid to this app",
                                             keyboard: "두벌식 / ANSI", intervalMilliseconds: intervalMS, results: results))
        try data.write(to: url, options: .atomic)
    }
}
