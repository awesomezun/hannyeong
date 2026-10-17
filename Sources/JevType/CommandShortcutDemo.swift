import SwiftUI

private struct ShortcutDemoPlayback: Equatable {
    let sequence: Int
    let active: Bool
    let reduceMotion: Bool
}

@MainActor
struct CommandShortcutDemos: View {
    var action: RightCommandGesture.Action? = nil
    var actionSequence = 0
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cycle = 0
    @State private var replay = 0
    @State private var replayAction: RightCommandGesture.Action?
    @State private var activeAction: RightCommandGesture.Action?

    var body: some View {
        HStack(spacing: 22) {
            CommandShortcutDemo(title: "한·영 반전", taps: 1, cycle: cycle,
                                active: isActive && (activeAction == nil || activeAction == .toggleLanguage), replay: restart)
            Divider().frame(height: 204)
            CommandShortcutDemo(title: "교정창 열기", taps: 2, cycle: cycle,
                                active: isActive && (activeAction == nil || activeAction == .correction), replay: restart)
        }
        .onChange(of: actionSequence) { _ in
            replayAction = action
            replay += 1
        }
        .task(id: ShortcutDemoPlayback(sequence: replay, active: isActive, reduceMotion: reduceMotion)) {
            guard isActive, !reduceMotion else { return }
            do {
                if let replayAction {
                    activeAction = replayAction
                    cycle += 1
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                } else {
                    try await Task.sleep(nanoseconds: replay == 0 ? 450_000_000 : 150_000_000)
                }
                while true {
                    activeAction = nil
                    cycle += 1
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                }
            } catch {
                if !(error is CancellationError) { AppSupport.shared.reportConfigurationError(error) }
            }
        }
    }

    private func restart() {
        replayAction = nil
        replay += 1
    }
}

@MainActor
private struct CommandShortcutDemo: View {
    let title: String
    let taps: Int
    let cycle: Int
    let active: Bool
    let replay: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    private var instruction: String {
        taps == 1 ? "오른쪽 Command 한 번" : "오른쪽 Command 빠르게 두 번"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Button(action: replay) {
                CommandKeycap(depression: pressed ? 8 : 0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title + ": " + instruction)
            .accessibilityValue(pressed ? "눌림" : "대기")
            .help("클릭해서 두 동작을 다시 보기")
            Text(instruction).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .task(id: ShortcutDemoPlayback(sequence: cycle, active: active, reduceMotion: reduceMotion)) {
            pressed = false
            guard cycle > 0, active, !reduceMotion else { return }
            do {
                for tap in 0..<taps {
                    withAnimation(.easeOut(duration: 0.08)) { pressed = true }
                    try await Task.sleep(nanoseconds: 120_000_000)
                    withAnimation(.easeOut(duration: 0.08)) { pressed = false }
                    if tap + 1 < taps { try await Task.sleep(nanoseconds: 100_000_000) }
                }
            } catch {
                pressed = false
                if !(error is CancellationError) { AppSupport.shared.reportConfigurationError(error) }
            }
        }
    }
}

private struct CommandKeycap: View, Animatable {
    var depression: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var animatableData: CGFloat {
        get { depression }
        set { depression = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            let dark = colorScheme == .dark
            // DSA proportions: a shallow spherical top and a short, gently flared skirt.
            let topTransform = CGAffineTransform(a: 1, b: 0.1, c: -0.18, d: 0.78,
                                                  tx: 34, ty: 17 + depression)
            let baseTransform = CGAffineTransform(a: 1, b: 0.1, c: -0.18, d: 0.78,
                                                   tx: 28, ty: 35)
            let topCorners = corners(width: 104, height: 82, transform: topTransform)
            let baseCorners = corners(width: 114, height: 88, transform: baseTransform)
            let body = Path(roundedRect: CGRect(x: 0, y: 0, width: 114, height: 88), cornerRadius: 22)
                .applying(baseTransform)
            let wall = sideWall(top: topTransform, base: baseTransform)
            let topLight = Color.white
            let topShade = Color(white: 0.965)
            let sideLight = Color(white: 0.92)
            let sideShade = Color(white: 0.8)
            let ink = Color(white: 0.3)

            var shadow = context
            shadow.addFilter(.shadow(color: .black.opacity(dark ? 0.25 : 0.12),
                                     radius: 6 - depression / 4, x: 2, y: 5 - depression / 4))
            shadow.fill(body, with: .linearGradient(
                Gradient(colors: [sideLight, sideShade]), startPoint: baseCorners[0], endPoint: baseCorners[2]))
            context.fill(wall, with: .linearGradient(
                Gradient(colors: [sideLight, sideShade]),
                startPoint: topCorners[0], endPoint: baseCorners[2]))

            let top = Path(roundedRect: CGRect(x: 0, y: 0, width: 104, height: 82), cornerRadius: 22)
                .applying(topTransform)
            context.fill(top, with: .linearGradient(
                Gradient(colors: [topLight, topShade]),
                startPoint: topCorners[0], endPoint: topCorners[2]))
            context.stroke(top, with: .color(.white.opacity(0.8)), lineWidth: 0.8)
            var dish = context
            dish.clip(to: top)
            dish.fill(top, with: .radialGradient(
                Gradient(colors: [ink.opacity(0.055), .clear]),
                center: CGPoint(x: 52, y: 40).applying(topTransform), startRadius: 2, endRadius: 64))

            var legend = context
            legend.transform = topTransform
            legend.draw(Text("⌘").font(.system(size: 31, weight: .medium, design: .rounded)).foregroundColor(ink),
                        at: CGPoint(x: 52, y: 32))
            legend.draw(Text("command").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(ink),
                        at: CGPoint(x: 52, y: 60))
        }
        .frame(width: 168, height: 140)
        .accessibilityHidden(true)
    }

    private func corners(width: CGFloat, height: CGFloat, transform: CGAffineTransform) -> [CGPoint] {
        [CGPoint.zero, CGPoint(x: width, y: 0), CGPoint(x: width, y: height), CGPoint(x: 0, y: height)]
            .map { $0.applying(transform) }
    }

    private func sideWall(top: CGAffineTransform, base: CGAffineTransform) -> Path {
        let radius: CGFloat = 22
        let curve = radius * 0.5522847498
        func upper(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(top) }
        func lower(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(base) }
        var path = Path()
        path.move(to: upper(0, radius))
        path.addLine(to: upper(0, 82 - radius))
        path.addCurve(to: upper(radius, 82), control1: upper(0, 82 - radius + curve),
                      control2: upper(radius - curve, 82))
        path.addLine(to: upper(104 - radius, 82))
        path.addCurve(to: upper(104, 82 - radius), control1: upper(104 - radius + curve, 82),
                      control2: upper(104, 82 - radius + curve))
        path.addLine(to: upper(104, radius))
        path.addLine(to: lower(114, radius))
        path.addLine(to: lower(114, 88 - radius))
        path.addCurve(to: lower(114 - radius, 88), control1: lower(114, 88 - radius + curve),
                      control2: lower(114 - radius + curve, 88))
        path.addLine(to: lower(radius, 88))
        path.addCurve(to: lower(0, 88 - radius), control1: lower(radius - curve, 88),
                      control2: lower(0, 88 - radius + curve))
        path.addLine(to: lower(0, radius))
        path.closeSubpath()
        return path
    }
}
