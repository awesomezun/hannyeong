import AppKit
import SwiftUI

@MainActor
struct TutorialView: View {
    let endEditing: () -> Void
    let finish: () -> Void
    @StateObject private var inputSources = TutorialInputSources()
    @State private var step = 0
    @State private var inputs = ["", "", ""]
    @State private var message = ""

    var body: some View {
        VStack(spacing: 0) {
            HannyeongWindowHeader()
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                    if step == 2 {
                        Text(instruction)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(height: 34)
                    }
                }
                if step == 0 {
                    inputSourceGuide
                } else {
                    if step == 2 {
                        HStack(spacing: 12) {
                            commandCard(taps: 1, title: "한·영 반전")
                            commandCard(taps: 2, title: "교정창 열기")
                        }
                    }
                    practiceCard
                }
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(height: 16)
            }
            .padding(.horizontal, 38)
            .frame(maxHeight: .infinity)
            footer
        }
        .frame(width: 640, height: 540)
        .background(.regularMaterial)
    }

    private var title: String {
        switch step {
        case 0: "한녕을 선택하세요."
        case 1: "한영키 없이, 그냥 타이핑"
        default: "결과를 바꾸고 싶을 때"
        }
    }

    private var instruction: String {
        "오른쪽 Command 키를 눌러보세요."
    }

    private var inputSourceGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("입력기 선택")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.leading, 12)
            inputSourceRow(.abc, glyph: "A")
            inputSourceRow(.hannyeong, glyph: "ㅎ")
        }
        .padding(16).frame(width: 360)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func inputSourceRow(_ source: TutorialInputSources.Source, glyph: String) -> some View {
        let selected = inputSources.selectedID == source.id
        return Button {
            endEditing()
            do {
                try inputSources.select(source)
                message = ""
            } catch {
                AppSupport.shared.reportConfigurationError(error)
                message = "입력기를 전환하지 못했습니다. 다시 선택해 주세요."
            }
        } label: {
            HStack(spacing: 14) {
                Text(glyph).font(.system(size: source == .hannyeong ? 20 : 23, weight: .semibold))
                    .frame(width: 40, height: 30)
                    .foregroundStyle(source == .hannyeong ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                    .background(source == .hannyeong ? Color.primary : Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                Text(source.name).font(.system(size: 17, weight: selected ? .semibold : .regular))
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14).frame(height: 56)
        }
        .buttonStyle(TutorialInputSourceButtonStyle(selected: selected))
        .accessibilityLabel(source.name + " 입력기로 전환")
        .accessibilityValue(selected ? "선택됨" : "선택되지 않음")
    }

    private func commandCard(taps: Int, title: String) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("⌘").font(.system(size: 25, weight: .medium))
                Text("오른쪽").font(.system(size: 11, weight: .medium))
            }
            .frame(width: 112, height: 42)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
            Text(taps == 1 ? "한 번 · 한·영 반전" : "빠르게 두 번 · 교정창")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(taps == 2 ? Color.accentColor : Color.primary)
        }
        .frame(maxWidth: .infinity).frame(height: 106)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
            taps == 2 ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("오른쪽 Command " + (taps == 1 ? "한 번: " : "빠르게 두 번: ") + title)
    }

    private var practiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("직접 입력해보기").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            TutorialPracticeField(text: Binding(get: { inputs[step] }, set: { inputs[step] = $0 }),
                                  placeholder: step == 1 ? "안녕 hello를 입력해보세요" : "단어 입력 뒤 Space를 누르세요",
                                  onBeginEditing: {
                                      do { try inputSources.applyToPractice() }
                                      catch {
                                          AppSupport.shared.reportConfigurationError(error)
                                          message = "입력기를 전환하지 못했습니다. 다시 선택해 주세요."
                                      }
                                  })
                .frame(height: 38)
                .padding(.horizontal, 12)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5))
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            ZStack {
                HStack {
                    Button { move(to: step - 1) } label: {
                        Label("이전", systemImage: "chevron.left").frame(width: 78)
                    }
                    .buttonStyle(HannyeongButtonStyle(kind: .secondary)).disabled(step == 0)
                    Spacer()
                    Button {
                        endEditing()
                        if step == 2 { finish() }
                        else { move(to: step + 1) }
                    } label: {
                        HStack(spacing: 8) {
                            Text(step == 2 ? "사용 시작" : "다음")
                            Image(systemName: step == 2 ? "checkmark" : "chevron.right")
                        }.frame(width: 86)
                    }
                    .buttonStyle(HannyeongButtonStyle(kind: .primary))
                }
                VStack(spacing: 5) {
                    Text("\(step + 1) / 3").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(0..<3) { index in
                            Capsule().fill(index == step ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: index == step ? 16 : 5, height: 5)
                        }
                    }.accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 32)
            .frame(height: 72)
        }
    }

    private func move(to nextStep: Int) {
        endEditing()
        step = nextStep
        message = ""
    }

}

private struct TutorialInputSourceButtonStyle: ButtonStyle {
    let selected: Bool
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.22 : hovered ? 0.16 : selected ? 0.1 : 0),
                        in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onHover { hovered = $0 }
    }
}

