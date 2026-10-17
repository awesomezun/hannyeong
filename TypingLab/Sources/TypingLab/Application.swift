import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = LabModel()
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("TypingLab launched")
        NSApp.setActivationPolicy(.regular)
        installMenus()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "TypingLab"; window.minSize = NSSize(width: 720, height: 730)
        window.contentView = NSHostingView(rootView: LabView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        model.load()
        if let index = CommandLine.arguments.firstIndex(of: "--smoke"), index + 1 < CommandLine.arguments.count {
            smoke(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--batch-smoke"), index + 1 < CommandLine.arguments.count {
            batchSmoke(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.refreshPermission() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func installMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "TypingLab 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(); editItem.title = "편집"; let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; menu.addItem(editItem); NSApp.mainMenu = menu
    }

    private func smoke(to url: URL, casesFile: String? = nil) {
        NSLog("TypingLab smoke started")
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1))
                model.sourceID = "com.yeop.inputmethod.JevType"
                model.expectedText = "안녕 slack chatgpt gpt\n지금 slack에서 작업 중ㅋㅋ\ngptㅋㅋㅋㅋ"
                if let casesFile {
                    model.expectedText = try String(contentsOfFile: casesFile, encoding: .utf8)
                }
                if let index = CommandLine.arguments.firstIndex(of: "--smoke-cases"), index + 1 < CommandLine.arguments.count {
                    model.expectedText = try String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8)
                }
                if let index = CommandLine.arguments.firstIndex(of: "--smoke-gate-file"), index + 1 < CommandLine.arguments.count {
                    let gate = CommandLine.arguments[index + 1]
                    let activationDeadline = Date().addingTimeInterval(120)
                    while !FileManager.default.fileExists(atPath: gate) {
                        guard Date() < activationDeadline else {
                            throw NSError(domain: "TypingLab.Smoke", code: 4,
                                          userInfo: [NSLocalizedDescriptionKey: "Native window activation was not confirmed"])
                        }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                }
                let sentenceCount = model.expectedText.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                model.repeats = 2
                model.start()
                guard model.running else { throw TypingError.permissionRequired }
                try await Task.sleep(for: .milliseconds(600))
                model.togglePause()
                try await Task.sleep(for: .milliseconds(100))
                let pausedText = model.editor?.string
                try await Task.sleep(for: .milliseconds(150))
                guard model.paused, model.editor?.string == pausedText else {
                    throw NSError(domain: "TypingLab.Smoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pause did not hold the typed text"])
                }
                model.togglePause()
                let deadline = Date().addingTimeInterval(90)
                while model.running {
                    guard Date() < deadline else { model.stop(); throw TypingError.compositionTimeout }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard model.results.count == sentenceCount * 2 else {
                    throw NSError(domain: "TypingLab.Smoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "Repeated run incomplete: \(model.status)"])
                }
                try model.save(to: url)
                model.start()
                try await Task.sleep(for: .milliseconds(450))
                model.stop()
                while model.running { try await Task.sleep(for: .milliseconds(50)) }
                model.repeats = 1
                model.start()
                while model.running {
                    guard Date() < deadline else { model.stop(); throw TypingError.compositionTimeout }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard model.results.count == sentenceCount else {
                    throw NSError(domain: "TypingLab.Smoke", code: 3, userInfo: [NSLocalizedDescriptionKey: "Restart incomplete: \(model.status)"])
                }
                try model.save(to: url.deletingLastPathComponent().appendingPathComponent("restart-smoke-result.json"))
                NSLog("TypingLab smoke PASS: pause, resume, repeated results, stop, restart, JSON export")
            } catch {
                let previousStatus = model.status
                model.report(error)
                do {
                    let data = try JSONSerialization.data(withJSONObject: ["error": String(describing: error),
                        "status": model.status, "previousStatus": previousStatus, "paused": model.paused,
                        "completedResults": model.results.count,
                        "postEventPermission": model.hasPermission], options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: url, options: .atomic)
                } catch { NSLog("TypingLab smoke result error: %@", String(describing: error)) }
            }
        }
    }

    private func batchSmoke(directory: URL) {
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var completed = ""
                while true {
                    let file = directory.appendingPathComponent("request.json")
                    if !FileManager.default.fileExists(atPath: file.path) {
                        try await Task.sleep(for: .milliseconds(100)); continue
                    }
                    let job = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String:String]
                    let id = job["id"]!
                    if id == completed { try await Task.sleep(for: .milliseconds(100)); continue }
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    let activationDeadline = Date().addingTimeInterval(600)
                    while !NSApp.isActive || window.isKeyWindow != true {
                        model.status = "실제 측정을 시작하려면 이 창을 직접 클릭해 앞으로 가져오세요."
                        guard Date() < activationDeadline else {
                            throw NSError(domain: "TypingLab.Batch", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: "TypingLab never became the active window"])
                        }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    if job["operation"] == "status" {
                        model.status = job["text"]!
                    } else if job["operation"] == "selectABC" {
                        model.sourceID = "com.apple.keylayout.ABC"
                        model.editor?.inputContext?.discardMarkedText()
                        model.editor?.unmarkText()
                        try model.selectSource()
                    } else if job["operation"] == "budget" {
                        try await model.measureBudget(configuration: URL(fileURLWithPath: job["configuration"]!))
                    } else if job["operation"] == "smoke" {
                        let output = URL(fileURLWithPath: job["output"]!)
                        smoke(to: output, casesFile: job["casesFile"])
                        let deadline = Date().addingTimeInterval(150)
                        let restarted = output.deletingLastPathComponent().appendingPathComponent("restart-smoke-result.json")
                        while !FileManager.default.fileExists(atPath: restarted.path) {
                            if FileManager.default.fileExists(atPath: output.path) {
                                let value = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as! [String:Any]
                                if value["error"] != nil {
                                    throw NSError(domain: "TypingLab.Batch", code: 2,
                                                  userInfo: [NSLocalizedDescriptionKey: "Actual smoke failed; see its JSON export"])
                                }
                            }
                            guard Date() < deadline else { throw TypingError.compositionTimeout }
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    } else {
                        throw NSError(domain: "TypingLab.Batch", code: 3,
                                      userInfo: [NSLocalizedDescriptionKey: "Unknown batch operation"])
                    }
                    completed = id
                    let response = try JSONSerialization.data(withJSONObject: ["id": id, "completed": true])
                    try response.write(to: directory.appendingPathComponent("response.json"), options: .atomic)
                }
            } catch {
                model.report(error)
                do {
                    let result = try JSONSerialization.data(withJSONObject: ["error": String(describing: error)])
                    try result.write(to: directory.appendingPathComponent("error.json"), options: .atomic)
                } catch { NSLog("TypingLab batch export failed: %@", String(describing: error)) }
            }
        }
    }
}

@main
struct TypingLabApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate(); app.delegate = delegate; app.run()
        withExtendedLifetime(delegate) {}
    }
}
