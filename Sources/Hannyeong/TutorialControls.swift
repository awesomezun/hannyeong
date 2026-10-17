import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class TutorialInputSources: NSObject, ObservableObject {
    enum Source {
        case abc, hannyeong

        var id: String {
            switch self {
            case .abc: "com.apple.keylayout.ABC"
            case .hannyeong: "com.yeop.inputmethod.Hannyeong"
            }
        }

        var name: String { self == .abc ? "ABC" : "한녕" }
    }

    @Published private(set) var selectedID = ""
    private var pendingPracticeSource: Source?

    override init() {
        super.init()
        refresh()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(inputSourceChanged(_:)),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    func select(_ target: Source) throws {
        try selectSource(target)
        pendingPracticeSource = target
    }

    func applyToPractice() throws {
        if let target = pendingPracticeSource {
            // macOS remembers the source for an existing field editor separately from the window.
            try selectSource(target)
            pendingPracticeSource = nil
        }
    }

    private func selectSource(_ target: Source) throws {
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        guard let source = sources.first(where: { sourceID($0) == target.id }) else {
            throw NSError(domain: "HannyeongInputSource", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Input source is not registered: \(target.id)"])
        }
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Input source selection failed: \(target.id), status=\(status)"])
        }
        refresh()
    }

    @objc private func inputSourceChanged(_ notification: Notification) { refresh() }

    private func refresh() {
        selectedID = sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    private func sourceID(_ source: TISInputSource) -> String {
        let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)!
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
}

@MainActor
struct TutorialKeyRecorder: NSViewRepresentable {
    let label: String
    let accessibilityLabel: String
    let emphasized: Bool
    let onRecord: (UInt16) -> Void
    let onRecordingChanged: (Bool) -> Void
    let onInvalidInput: () -> Void

    func makeNSView(context: Context) -> TutorialKeyButton {
        let button = TutorialKeyButton()
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    func updateNSView(_ button: TutorialKeyButton, context: Context) {
        button.savedLabel = label
        button.emphasized = emphasized
        button.onRecord = onRecord
        button.onRecordingChanged = onRecordingChanged
        button.onInvalidInput = onInvalidInput
        if !button.isRecording { button.title = label }
    }
}

@MainActor
final class TutorialKeyButton: NSButton {
    var emphasized = false { didSet { needsDisplay = true } }
    override var title: String { didSet { needsDisplay = true } }
    var savedLabel = ""
    var onRecord: ((UInt16) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onInvalidInput: (() -> Void)?
    private(set) var isRecording = false
    private var hovered = false
    private var hoverTracking: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        isBordered = false
        focusRingType = .none
        font = .monospacedSystemFont(ofSize: 17, weight: .semibold)
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) { fatalError("TutorialKeyButton does not use a storyboard") }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let focused = window?.firstResponder === self && window?.isKeyWindow == true
            let accent = NSColor.controlAccentColor
            let highlighted = hovered || isRecording || isHighlighted
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
            (emphasized || highlighted ? accent.withAlphaComponent(highlighted ? 0.2 : 0.1) : NSColor.labelColor.withAlphaComponent(0.065)).setFill()
            path.fill()
            (focused || isRecording ? accent : NSColor.labelColor.withAlphaComponent(highlighted ? 0.25 : 0.13)).setStroke()
            path.lineWidth = focused || isRecording ? 2 : 1
            path.stroke()
            let label = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: isRecording ? 13 : 16, weight: .semibold),
                .foregroundColor: emphasized || highlighted ? accent : NSColor.labelColor
            ])
            let size = label.size()
            label.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }
    }

    @objc private func beginRecording() {
        window?.makeFirstResponder(self)
        isRecording = true
        title = "키 입력…"
        onRecordingChanged?(true)
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        title = savedLabel
        onRecordingChanged?(false)
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode != 53 {
            if ShortcutSettings.options.contains(where: { $0.code == event.keyCode }),
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                onRecord?(event.keyCode)
            } else { onInvalidInput?() }
        }
        window?.makeFirstResponder(nil)
    }
}

@MainActor
struct TutorialPracticeField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var accessibilityLabel = "한녕 입력 연습"
    let onBeginEditing: () -> Void
    var onCommandAction: ((RightCommandGesture.Action) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.font = .systemFont(ofSize: 20)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderAttributedString = NSAttributedString(string: placeholder,
                                                               attributes: [.font: field.font!, .foregroundColor: NSColor.secondaryLabelColor])
        field.setAccessibilityLabel(accessibilityLabel)
        field.delegate = context.coordinator
        if onCommandAction != nil { context.coordinator.observeCommandActions(for: field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderAttributedString = NSAttributedString(string: placeholder,
                                                               attributes: [.font: field.font!, .foregroundColor: NSColor.secondaryLabelColor])
        field.setAccessibilityLabel(accessibilityLabel)
        if field.currentEditor() == nil && field.stringValue != text { field.stringValue = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TutorialPracticeField
        private weak var field: NSTextField?
        init(_ parent: TutorialPracticeField) { self.parent = parent }

        deinit { NotificationCenter.default.removeObserver(self) }

        func observeCommandActions(for field: NSTextField) {
            self.field = field
            NotificationCenter.default.addObserver(self, selector: #selector(commandAction(_:)),
                                                   name: RightCommandGesture.actionNotification, object: nil)
        }

        @objc private func commandAction(_ notification: Notification) {
            guard let field, let editor = field.currentEditor(),
                  field.window?.isKeyWindow == true, field.window?.firstResponder === editor,
                  let action = notification.object as? RightCommandGesture.Action else { return }
            parent.onCommandAction?(action)
        }

        func controlTextDidBeginEditing(_ notification: Notification) { parent.onBeginEditing() }

        func controlTextDidChange(_ notification: Notification) { readText(notification) }
        func controlTextDidEndEditing(_ notification: Notification) { readText(notification) }

        private func readText(_ notification: Notification) {
            let field = notification.object as! NSTextField
            parent.text = field.stringValue
        }
    }
}
