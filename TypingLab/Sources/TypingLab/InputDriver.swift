import AppKit
import Carbon

struct InputSourceInfo: Identifiable {
    let id: String
    let name: String
    let source: TISInputSource
}

enum InputSources {
    static func string(_ source: TISInputSource, _ key: CFString) throws -> String {
        guard let pointer = TISGetInputSourceProperty(source, key) else { throw TypingError.sourceUnavailable }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
    static func current() throws -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { throw TypingError.sourceUnavailable }
        return try string(source, kTISPropertyInputSourceID)
    }
    static func available() throws -> [InputSourceInfo] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            throw TypingError.sourceUnavailable
        }
        return try list.compactMap { source in
            guard try string(source, kTISPropertyInputSourceCategory) == kTISCategoryKeyboardInputSource as String else { return nil }
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()) else { return nil }
            return try InputSourceInfo(id: string(source, kTISPropertyInputSourceID),
                                       name: string(source, kTISPropertyLocalizedName), source: source)
        }
    }
}

enum TypingError: LocalizedError {
    case sourceUnavailable, sourceChanged, permissionRequired, eventCreation, compositionTimeout, noText
    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: return "선택한 입력기를 사용할 수 없습니다. 시스템에서 입력기를 추가한 뒤 앱을 다시 열어 주세요."
        case .sourceChanged: return "실행 중 입력기가 변경되어 중단했습니다. 입력기를 선택하고 다시 시작해 주세요."
        case .permissionRequired: return "자동 타이핑하려면 TypingLab의 손쉬운 사용 권한을 허용해 주세요."
        case .eventCreation: return "키보드 이벤트를 생성하지 못했습니다. 타이핑을 중단했습니다."
        case .compositionTimeout: return "입력기의 변환 완료를 확인하지 못해 중단했습니다. 아래 입력 내용을 확인해 주세요."
        case .noText: return "위쪽 칸에 테스트할 문장을 붙여넣어 주세요."
        }
    }
}
