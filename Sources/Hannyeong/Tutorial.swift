import AppKit
import SwiftUI

@MainActor
final class TutorialWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "한녕 사용법"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("TutorialWindowController does not use a storyboard")
    }

    override func showWindow(_ sender: Any?) {
        if window!.contentViewController == nil {
            window!.contentViewController = NSHostingController(rootView: TutorialView(
                endEditing: { [weak self] in self?.window?.makeFirstResponder(nil) },
                finish: { [weak self] in self?.window?.performClose(nil) }
            ))
        }
        super.showWindow(sender)
    }

    func windowWillClose(_ notification: Notification) {
        // The input method stays running after the tutorial closes.
        window?.contentViewController = nil
    }
}
