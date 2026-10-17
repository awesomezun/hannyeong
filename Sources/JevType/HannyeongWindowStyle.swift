import AppKit
import SwiftUI

@MainActor
struct HannyeongWindowHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().scaledToFit().frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text("한녕").font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 34)
    }
}

struct HannyeongButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let prominent = kind == .primary
        let active = hovered || configuration.isPressed
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary.opacity(enabled ? 0.85 : 0.3))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(prominent ? Color.accentColor.opacity(active ? 0.8 : 1) : Color.primary.opacity(enabled && active ? 0.12 : 0.055),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(prominent ? Color.white.opacity(0.12) : Color.primary.opacity(enabled ? 0.09 : 0.04)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .onHover { hovered = $0 }
    }
}
