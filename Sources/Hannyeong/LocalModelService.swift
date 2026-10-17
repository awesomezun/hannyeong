import Foundation
import HannyeongCore

@MainActor
enum LocalModelService {
    private static var cached: LocalDecisionClient?

    static func client() throws -> LocalDecisionClient {
        if let cached { return cached }
        guard let url = Bundle.main.url(forResource: "local-runtime", withExtension: "json") else {
            throw LocalDecisionError(detail: "Local model runtime is not installed")
        }
        let saved = try JSONDecoder().decode(LocalRuntimeConfiguration.self, from: Data(contentsOf: url))
        let resources = url.deletingLastPathComponent()
        // Release builds bundle Python and store its path relative to Resources.
        let python = saved.python.hasPrefix("/") ? saved.python : resources.appendingPathComponent(saved.python).path
        let runtime = LocalRuntimeConfiguration(python: python,
            worker: resources.appendingPathComponent(saved.worker).path,
            model: resources.appendingPathComponent(saved.model).path)
        let personal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Hannyeong/local-b3-session-personal.json")
        let client = LocalDecisionClient(runtime: runtime, personalURL: personal)
        cached = client
        return client
    }
}
