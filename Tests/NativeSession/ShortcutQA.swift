import AppKit
import HannyeongCore

@main
private struct ShortcutQA {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try run()
            print("PASS default keys, persistence, duplicate rejection, remapped native commits, host modifiers and correction scope")
        } catch {
            fputs("Shortcut QA failed: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() throws {
        let suite = "HannyeongShortcutQA." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = ShortcutSettings(defaults: defaults)
        try require(shortcuts.label(for: .original) == "F6" &&
                    shortcuts.label(for: .hangul) == "F7" &&
                    shortcuts.label(for: .correction) == "F8", "Factory keys changed")
        try shortcuts.assign(109, to: .original)
        try shortcuts.assign(103, to: .hangul)
        try shortcuts.assign(111, to: .correction)
        let reloaded = ShortcutSettings(defaults: defaults)
        try require(reloaded.label(for: .original) == "F10" &&
                    reloaded.label(for: .hangul) == "F11" &&
                    reloaded.label(for: .correction) == "F12", "Keys were not persisted")
        var rejected = false
        do { try shortcuts.assign(111, to: .original) } catch { rejected = true }
        try require(rejected && shortcuts.code(for: .original) == 109, "Duplicate assignment changed the key")
        rejected = false
        do { try shortcuts.assign(0, to: .original) } catch { rejected = true }
        try require(rejected && shortcuts.code(for: .original) == 109, "Non-function key was accepted")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CorrectionStore(url: folder.appendingPathComponent("corrections.json"))
        for (code, expected) in [(UInt16(109), "dkssud"), (UInt16(103), "안녕")] {
            let view = NativeTextView(frame: .zero)
            let session = CompositionSession(client: view, shortcuts: shortcuts, corrections: store) {
                fatalError("Unexpected model call during forced commit: \($0)")
            }
            for character in "dkssud" {
                try require(session.handle(event(code: 0, text: String(character))), "Letter was not handled")
            }
            try require(!session.handle(event(code: 97)), "Old F6 still committed the composition")
            try require(session.handle(event(code: code)), "Remapped key was not consumed")
            try require(view.string == expected && !view.hasMarkedText(), "Remapped key committed \(view.string), expected \(expected)")
        }
        let host = NativeTextView(frame: .zero)
        let session = CompositionSession(client: host, shortcuts: shortcuts, corrections: store) {
            fatalError("Unexpected error: \($0)")
        }
        for character in "dkssud" { _ = session.handle(event(code: 0, text: String(character))) }
        try require(!session.handle(event(code: 109, flags: .command)) && host.string == "안녕",
                    "Command-modified function key did not reach the host")
        for character in "dkssud" { _ = session.handle(event(code: 0, text: String(character))) }
        try shortcuts.assign(101, to: .original)
        try require(!session.handle(event(code: 109)), "An active session retained the old original key")
        try require(session.handle(event(code: 101)) && host.string == "안녕dkssud" && !host.hasMarkedText(),
                    "A key changed during composition was not applied immediately")
        try require(shortcuts.correctionScope(for: event(code: 111)) == .context, "Correction context scope failed")
        try require(shortcuts.correctionScope(for: event(code: 111, flags: .shift)) == .always, "Shift correction scope failed")
        try require(shortcuts.correctionScope(for: event(code: 100)) == nil, "Old F8 still opened correction")
        for flags: NSEvent.ModifierFlags in [.command, .control, .option] {
            try require(shortcuts.correctionScope(for: event(code: 111, flags: flags)) == nil,
                        "Modified correction key did not remain host-owned")
        }
    }

    private static func event(code: UInt16, text: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                        timestamp: 0, windowNumber: 0, context: nil, characters: text,
                        charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }

    private static func require(_ condition: Bool, _ detail: String) throws {
        if !condition { throw LocalDecisionError(detail: detail) }
    }
}
