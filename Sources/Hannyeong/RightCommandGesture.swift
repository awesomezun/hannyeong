import AppKit

/// Modifier events stay with the host. Only a short, unaccompanied right Command tap is an action.
@MainActor
final class RightCommandGesture {
    enum Action { case toggleLanguage, correction }
    static let actionNotification = Notification.Name("HannyeongRightCommandAction")
    private let perform: (Action) -> Void
    private var pressedAt: TimeInterval?
    private var firstRelease: TimeInterval?
    private var pending: Task<Void, Never>?
    private let doubleTapInterval: TimeInterval = 0.25

    init(perform: @escaping (Action) -> Void) { self.perform = perform }

    func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged else {
            cancel()
            return
        }
        // IMK keeps keyCode=54 but strips device-specific modifier bits across its client boundary.
        guard event.keyCode == 54 else { cancel(); return }
        let rightDown = event.modifierFlags.contains(.command)
        if rightDown {
            let otherModifiers = event.modifierFlags.intersection([.shift, .control, .option])
            guard otherModifiers.isEmpty, event.modifierFlags.rawValue & 0x08 == 0 else {
                cancel()
                return
            }
            pressedAt = event.timestamp
        } else {
            guard let down = pressedAt else { return }
            pressedAt = nil
            guard event.timestamp - down <= 0.5 else { cancel(); return }
            if let release = firstRelease, down - release <= doubleTapInterval {
                cancel()
                perform(.correction)
            } else {
                cancel()
                firstRelease = event.timestamp
                pending = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .milliseconds(250)) }
                    catch { return } // Task.sleep only throws when this tap was cancelled.
                    guard let self else { return }
                    // A second press has begun: wait for its release rather than toggling halfway.
                    if self.pressedAt != nil { return }
                    self.firstRelease = nil
                    self.pending = nil
                    self.perform(.toggleLanguage)
                }
            }
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        pressedAt = nil
        firstRelease = nil
    }
}
