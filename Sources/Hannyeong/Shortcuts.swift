import AppKit
import Combine
import HannyeongCore

@MainActor
final class ShortcutSettings: ObservableObject {
    enum Action: String, CaseIterable {
        case original, hangul, correction

        var title: String {
            switch self {
            case .original: "원문으로 확정"
            case .hangul: "한글로 확정"
            case .correction: "방금 변환 고치기"
            }
        }

        var defaultCode: UInt16 {
            switch self {
            case .original: 97
            case .hangul: 98
            case .correction: 100
            }
        }
    }

    static let shared = ShortcutSettings()
    static let didChange = Notification.Name("HannyeongShortcutsChanged")
    static let options: [(label: String, code: UInt16)] = [
        ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118),
        ("F5", 96), ("F6", 97), ("F7", 98), ("F8", 100),
        ("F9", 101), ("F10", 109), ("F11", 103), ("F12", 111)
    ]

    private let defaults: UserDefaults
    @Published private var codes: [Action: UInt16] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Dictionary(uniqueKeysWithValues: Action.allCases.map {
            ("shortcut." + $0.rawValue, Int($0.defaultCode))
        }))
        for action in Action.allCases {
            codes[action] = UInt16(defaults.integer(forKey: "shortcut." + action.rawValue))
        }
    }

    func code(for action: Action) -> UInt16 { codes[action]! }

    func label(for action: Action) -> String {
        Self.options.first { $0.code == code(for: action) }!.label
    }

    func assign(_ code: UInt16, to action: Action) throws {
        guard Self.options.contains(where: { $0.code == code }) else { throw ShortcutError.invalidKey }
        guard !Action.allCases.contains(where: { $0 != action && self.code(for: $0) == code }) else {
            throw ShortcutError.alreadyAssigned
        }
        codes[action] = code
        defaults.set(Int(code), forKey: "shortcut." + action.rawValue)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func correctionScope(for event: NSEvent) -> CorrectionScope? {
        guard event.keyCode == code(for: .correction),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        return event.modifierFlags.contains(.shift) ? .always : .context
    }
}

private enum ShortcutError: Error {
    case invalidKey, alreadyAssigned
}
