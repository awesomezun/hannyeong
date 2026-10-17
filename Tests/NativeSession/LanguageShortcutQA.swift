import AppKit
import JevIMECore

@main
private struct LanguageShortcutQA {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await run()
                print("PASS F6/F7 before and after Space, repeated toggles, queued words, cancellation, host edits and unchanged personal corrections")
                exit(0)
            } catch {
                fputs("Language shortcut QA failed: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    @MainActor private static func run() async throws {
        let suite = "HannyeongLanguageShortcutQA." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = ShortcutSettings(defaults: defaults)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CorrectionStore(url: folder.appendingPathComponent("corrections.json"))
        try store.record(raw: "dkssud", before: "", rejected: "dkssud", preferred: "안녕", scope: .always)
        try store.record(raw: "hello", before: "", rejected: "ㅗ디ㅣㅐ", preferred: "hello", scope: .always)
        let personalBefore = try Data(contentsOf: store.url)

        func fixture() -> (NativeTextView, CompositionSession, NSMutableArray) {
            let view = NativeTextView(frame: .zero)
            view.string = "앞말 "
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            let errors = NSMutableArray()
            let session = CompositionSession(client: view, shortcuts: shortcuts, corrections: store) { errors.add($0) }
            return (view, session, errors)
        }
        func type(_ text: String, in session: CompositionSession) {
            for char in text { _ = session.handle(key(0, String(char))) }
        }
        for flags: NSEvent.ModifierFlags in [[], .function] {
            let (hangulView, hangulSession, hangulErrors) = fixture()
            type("dkssud", in: hangulSession)
            try require(hangulSession.handle(key(98, flags: flags)), "F7 was not consumed before Space")
            try require(hangulView.string == "앞말 안녕" && !hangulView.hasMarkedText() && hangulErrors.count == 0,
                        "F7 before Space did not commit Hangul")
            let (view, session, errors) = fixture()
            type("dkssud", in: session)
            try require(session.handle(key(97, flags: flags)), "F6 was not consumed before Space")
            try require(view.string == "앞말 dkssud" && !view.hasMarkedText(), "F6 before Space did not commit original")
            _ = session.handle(key(98, flags: flags))
            try require(view.string == "앞말 안녕", "F7 could not change an F6 commit")
            _ = session.handle(key(49, " "))
            _ = session.handle(key(97, flags: flags))
            try require(view.string == "앞말 dkssud ", "F6 did not preserve the trailing Space")
            _ = session.handle(key(98, flags: flags))
            try require(view.string == "앞말 안녕 ", "F7 after Space did not restore Hangul")
            try require(errors.count == 0, "Unexpected forced-commit error: \(errors)")
        }
        let (view, session, errors) = fixture()
        type("dkssud ", in: session)
        try await wait(view, errors)
        try require(view.string == "앞말 안녕 ", "Saved correction did not commit")
        _ = session.handle(key(97))
        try require(view.string == "앞말 dkssud ", "F6 after the asynchronous Space commit did not change the word")
        _ = session.handle(key(98))
        try require(view.string == "앞말 안녕 ", "F7 after the asynchronous Space commit did not change the word")
        session.commitPending()
        session.suspend()
        try require(session.belongsTo(view) && !session.belongsTo(NativeTextView(frame: .zero)),
                    "Suspended session was reused for a different client")
        session.resume()
        _ = session.handle(key(97))
        try require(view.string == "앞말 dkssud ", "The same client's reactivation discarded the completed word")
        _ = session.handle(key(98))
        try require(view.string == "앞말 안녕 ", "Reactivated F7 did not restore Hangul")
        // The language keys also cancel an in-flight Space decision without a late overwrite.
        type("hello dkssud ", in: session)
        _ = session.handle(key(97))
        try await Task.sleep(for: .milliseconds(50))
        try require(view.string == "앞말 안녕 hello dkssud ", "Queued forced original was overwritten")
        _ = session.handle(key(98))
        try require(view.string == "앞말 안녕 hello 안녕 ", "Recent-word replacement changed earlier words")
        try require(errors.count == 0, "Unexpected queued-commit error: \(errors)")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let unchanged = view.string
        _ = session.handle(key(97))
        try require(view.string == unchanged && errors.count == 1, "Moved caret silently replaced a word")

        let (hostView, hostSession, hostErrors) = fixture()
        type("hello ", in: hostSession)
        try await wait(hostView, hostErrors)
        try require(!hostSession.handle(key(0, flags: .command)), "Command key was consumed")
        hostSession.commitPending()
        hostSession.deactivate()
        try require(hostView.string == "앞말 hello ", "Host commitment or shutdown retroactively forced Hangul")
        try require(try Data(contentsOf: store.url) == personalBefore, "Language keys modified personal corrections")
    }

    @MainActor private static func wait(_ view: NativeTextView, _ errors: NSMutableArray) async throws {
        for _ in 0..<100 {
            try require(errors.count == 0, "Unexpected decision error: \(errors)")
            if !view.hasMarkedText() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw LocalDecisionError(detail: "Space commitment did not finish")
    }

    private static func key(_ code: UInt16, _ text: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                        windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                        isARepeat: false, keyCode: code)!
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw LocalDecisionError(detail: message) }
    }
}
