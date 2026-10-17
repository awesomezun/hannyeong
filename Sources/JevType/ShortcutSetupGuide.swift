import AppKit
import SwiftUI

@MainActor
struct ShortcutSetupGuide: View {
    @Environment(\.dismiss) private var dismiss
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("한영키 설정 안내").font(.system(size: 22, weight: .bold))
            guideStep(title: "1. 입력 소스 전환 끄기",
                      image: "InputSourceShortcutGuide", height: 170,
                      instruction: "키보드 단축키 → 입력 소스에서 관련된 항목을 꺼주세요",
                      button: "키보드 설정 열기", action: openKeyboardSettings)
            guideStep(title: "2. 오른쪽 Command 매핑 삭제하기",
                      image: "KarabinerCommandGuide", height: 130,
                      instruction: "Karabiner-Elements를 사용한다면 오른쪽 커맨드와 관련된 항목을 삭제해주세요",
                      button: "Karabiner 설정 열기", action: openKarabiner)
            if let launchError {
                Text(launchError).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                Spacer()
                Button("완료") { dismiss() }
                    .buttonStyle(SettingsSmallButtonStyle(prominent: true))
                    .focusable(false)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 900)
        .background(.regularMaterial)
        .tint(SettingsAppearance.accent)
    }

    private func guideStep(title: String, image: String, height: CGFloat, instruction: String,
                           button: String, action: @escaping () -> Void) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 16, weight: .semibold))
                HStack(spacing: 20) {
                    Image(nsImage: NSImage(contentsOf: Bundle.main.url(forResource: image,
                                                                     withExtension: "png")!)!)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .frame(maxWidth: .infinity).frame(height: height)
                        .accessibilityLabel(title + " 설정 예시")
                    VStack(alignment: .leading, spacing: 14) {
                        Text(instruction).font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(button, action: action)
                            .buttonStyle(SettingsSmallButtonStyle(prominent: true))
                            .focusable(false)
                    }
                    .frame(width: 180, alignment: .leading)
                }
            }
        }
    }

    private func openKeyboardSettings() {
        launchError = nil
        let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!
        if !NSWorkspace.shared.open(url) {
            let error = NSError(domain: "HannyeongShortcutGuide", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "NSWorkspace rejected the Keyboard Shortcuts settings URL"])
            AppSupport.shared.reportConfigurationError(error)
            launchError = "키보드 단축키 창을 열지 못했습니다."
        }
    }

    private func openKarabiner() {
        launchError = nil
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.pqrs.Karabiner-Elements.Settings") else {
            let error = NSError(domain: "HannyeongShortcutGuide", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Karabiner-Elements Settings application is not installed"])
            AppSupport.shared.reportConfigurationError(error)
            launchError = "Karabiner-Elements가 설치되어 있지 않습니다."
            return
        }
        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
            } catch {
                AppSupport.shared.reportConfigurationError(error)
                launchError = "Karabiner 설정을 열지 못했습니다."
            }
        }
    }
}
