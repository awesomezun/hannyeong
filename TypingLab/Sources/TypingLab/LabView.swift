import AppKit
import SwiftUI
import TypingLabCore

struct TypingEditor: NSViewRepresentable {
    let model: LabModel
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let editor = MeasuredTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 180))
        editor.isRichText = false; editor.font = .systemFont(ofSize: 17)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor; model.editor = editor
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

struct LabView: View {
    @ObservedObject var model: LabModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TypingLab").font(.title2.bold())
                    Text("문장을 붙여넣고, 입력기의 실제 타이핑 결과를 확인하세요.").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                Picker("입력기", selection: $model.sourceID) {
                    ForEach(model.sources) { source in Text(source.name).tag(source.id) }
                }.frame(maxWidth: 270)
                HStack(spacing: 8) {
                    Text("속도")
                    Slider(value: $model.intervalMS, in: 15...150, step: 5).frame(width: 110)
                    Text("\(Int(model.intervalMS)) ms/키").monospacedDigit().frame(width: 78)
                }
                Stepper("\(model.repeats)회", value: $model.repeats, in: 1...10).frame(width: 80)
            }.disabled(model.running)
            if !model.hasPermission {
                HStack {
                    Image(systemName: "hand.raised").foregroundStyle(.orange)
                    Text("자동 타이핑에 손쉬운 사용 권한이 필요합니다.")
                    Spacer()
                    Button("권한 허용") { model.requestPermission() }
                    Button("다시 확인") { model.refreshPermission() }
                }.padding(10).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            GroupBox {
                TextEditor(text: $model.expectedText).font(.system(size: 15))
                    .frame(minHeight: 110, maxHeight: 150).disabled(model.running)
                    .padding(6)
            } label: {
                Label("테스트 문장 · 여기에 붙여넣기", systemImage: "doc.on.clipboard")
            }
            Text("한 줄에 한 문장씩 테스트합니다. 아래 칸을 문장마다 비우고 결과를 기록합니다.")
                .font(.caption).foregroundStyle(.secondary)
            GroupBox {
                TypingEditor(model: model).frame(minHeight: 165, maxHeight: .infinity)
            } label: { Label("실제 타이핑", systemImage: "text.cursor") }
            HStack {
                Button { model.start() } label: { Label("시작", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(model.running)
                Button(model.paused ? "재개" : "일시정지") { model.togglePause() }.disabled(!model.running)
                Button("중단") { model.stop() }.disabled(!model.running)
                Spacer()
                Text("\(model.results.filter(\.passed).count) / \(model.results.count) 일치")
                    .monospacedDigit().foregroundStyle(.secondary)
                Button("결과 저장") { model.saveResults() }.disabled(model.results.isEmpty || model.running)
            }
            ProgressView(value: model.progress)
            Text(model.status).font(.callout).textSelection(.enabled)
            if !model.exportStatus.isEmpty { Text(model.exportStatus).font(.caption).foregroundStyle(.secondary) }
            if !model.results.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.results) { result in resultRow(result) }
                    }
                }.frame(height: 145)
            }
        }.padding(20).frame(minWidth: 680, minHeight: 680)
    }
    private func resultRow(_ result: TestResult) -> some View {
        let diff = Comparison.differences(result.expected, result.actual)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(result.iteration)회 · \(result.sentenceNumber)번").foregroundStyle(.secondary)
                Label(result.passed ? "일치" : "차이 있음", systemImage: result.passed ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(result.passed ? .green : .orange)
            }.font(.caption)
            HStack(alignment: .top) { Text("원문").foregroundStyle(.secondary).frame(width: 30); styled(diff.expected) }
            HStack(alignment: .top) { Text("결과").foregroundStyle(.secondary).frame(width: 30); styled(diff.actual) }
        }.font(.system(size: 13)).textSelection(.enabled).padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
    private func styled(_ pieces: [DiffPiece]) -> Text {
        pieces.reduce(Text("")) { text, piece in text + Text(piece.text).foregroundColor(piece.changed ? .red : .primary) }
    }
}
