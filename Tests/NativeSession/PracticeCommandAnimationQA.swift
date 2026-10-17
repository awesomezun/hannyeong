import AppKit
import SwiftUI

@main
private struct PracticeCommandAnimationQA {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        Task { @MainActor in
            do {
                try await run()
                print("PASS resolved single/double actions reach only the focused practice field; Command chords, other fields, inactive windows and disposed coordinators do not trigger playback")
                exit(0)
            } catch {
                fputs("Practice Command animation QA failed: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    @MainActor private static func run() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                              styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 280, height: 40))
        let other = NSTextField(frame: NSRect(x: 10, y: 60, width: 280, height: 40))
        window.contentView!.addSubview(field)
        window.contentView!.addSubview(other)
        var actions: [RightCommandGesture.Action] = []
        let practice = TutorialPracticeField(text: .constant(""), placeholder: "안녕 hello",
                                             onBeginEditing: {}, onCommandAction: { actions.append($0) })
        var coordinator: TutorialPracticeField.Coordinator? = practice.makeCoordinator()
        weak var releasedCoordinator = coordinator
        coordinator!.observeCommandActions(for: field)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(150))
        try require(window.makeFirstResponder(field) && field.currentEditor() != nil && window.isKeyWindow,
                    "Could not focus the native practice field: editor=\(field.currentEditor() != nil), key=\(window.isKeyWindow)")
        let gesture = RightCommandGesture { action in
            NotificationCenter.default.post(name: RightCommandGesture.actionNotification, object: action)
        }
        func tap(_ start: Double) {
            gesture.handle(event(.flagsChanged, 54, flags: .command, at: start))
            gesture.handle(event(.flagsChanged, 54, at: start + 0.04))
        }
        tap(1)
        try require(actions.isEmpty, "Playback started before single/double tap resolution")
        try await Task.sleep(for: .milliseconds(300))
        try require(actions == [.toggleLanguage], "Single tap did not request only reversal playback")
        actions.removeAll()
        tap(2); tap(2.15)
        try await Task.sleep(for: .milliseconds(300))
        try require(actions == [.correction], "Double tap requested reversal or missed correction playback")
        actions.removeAll()
        for code: UInt16 in [8, 9] {
            gesture.handle(event(.flagsChanged, 54, flags: .command, at: 3))
            gesture.handle(event(.keyDown, code, flags: .command, at: 3.05))
            gesture.handle(event(.flagsChanged, 54, at: 3.1))
        }
        try await Task.sleep(for: .milliseconds(300))
        try require(actions.isEmpty, "Copy/paste triggered keycap playback")
        try require(window.makeFirstResponder(other), "Could not move to another field")
        tap(4)
        try await Task.sleep(for: .milliseconds(300))
        try require(actions.isEmpty, "A different field triggered practice playback")
        try require(window.makeFirstResponder(field), "Could not refocus practice")
        window.resignKey()
        tap(5)
        try await Task.sleep(for: .milliseconds(300))
        try require(actions.isEmpty, "An inactive settings window triggered playback")
        window.becomeKey()
        coordinator = nil
        try require(releasedCoordinator == nil, "Notification observer retained its coordinator")
        tap(6)
        try await Task.sleep(for: .milliseconds(300))
        try require(actions.isEmpty, "Disposed practice view still received actions")
    }

    private static func event(_ type: NSEvent.EventType, _ code: UInt16,
                              flags: NSEvent.ModifierFlags = [], at timestamp: Double) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: timestamp,
                        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                        isARepeat: false, keyCode: code)!
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "PracticeCommandAnimationQA", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
