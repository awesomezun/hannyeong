import AppKit
import JevIMECore

@main
private struct TutorialControlsQA {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try run()
            print("PASS native key capture, immediate persistence, Escape cancellation, invalid key and duplicate rejection")
        } catch {
            fputs("Tutorial controls QA failed: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() throws {
        let suite = "HannyeongTutorialControlsQA." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: .titled, backing: .buffered, defer: false)
        let button = TutorialKeyButton()
        window.contentView!.addSubview(button)
        button.savedLabel = settings.label(for: .original)
        var assigned = 0
        var invalid = 0
        var duplicates = 0
        button.onInvalidInput = { invalid += 1 }
        button.onRecord = { code in
            do {
                try settings.assign(code, to: .original)
                button.savedLabel = settings.label(for: .original)
                assigned += 1
            } catch { duplicates += 1 }
        }
        try require(window.makeFirstResponder(button) && !button.isRecording, "Keyboard focus started recording automatically")
        button.performClick(nil)
        try require(button.isRecording, "Click did not start recording")
        button.keyDown(with: event(109))
        try require(assigned == 1 && !button.isRecording && button.title == "F10" &&
                    ShortcutSettings(defaults: defaults).code(for: .original) == 109,
                    "F10 was not captured, displayed and persisted")
        button.performClick(nil)
        button.keyDown(with: event(53))
        try require(assigned == 1 && button.title == "F10" && !button.isRecording,
                    "Escape changed the shortcut")
        button.performClick(nil)
        button.keyDown(with: event(0))
        try require(invalid == 1 && assigned == 1 && button.title == "F10", "A letter was recorded")
        button.performClick(nil)
        button.keyDown(with: event(98))
        try require(duplicates == 1 && settings.label(for: .original) == "F10" && button.title == "F10",
                    "Duplicate key changed the displayed or saved shortcut")
    }

    private static func event(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                        isARepeat: false, keyCode: code)!
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw LocalDecisionError(detail: message) }
    }
}
