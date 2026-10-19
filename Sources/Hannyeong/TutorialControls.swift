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
