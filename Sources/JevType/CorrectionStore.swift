import Foundation
import JevIMECore

@MainActor
final class CorrectionStore {
    static let shared = CorrectionStore(url: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/JevType/corrections.json"))

    let url: URL

    init(url: URL) { self.url = url }

    func load() throws -> CorrectionMemory {
        guard FileManager.default.fileExists(atPath: url.path) else { return CorrectionMemory() }
        return try JSONDecoder().decode(CorrectionMemory.self, from: Data(contentsOf: url))
    }

    func record(raw: String, before: String, rejected: String, preferred: String, scope: CorrectionScope) throws {
        var memory = try load()
        try memory.record(raw: raw, before: before, rejected: rejected, preferred: preferred, scope: scope)
        try save(memory)
    }

    func remove(_ entry: CorrectionExample) throws {
        try remove([entry])
    }

    func changeScope(of entry: CorrectionExample, to scope: CorrectionScope,
                     local: LocalDecisionClient) async throws -> CorrectionExample {
        guard try load().entries.contains(entry) else { throw CorrectionMemoryError.missingRecord }
        _ = try await local.changeScope(of: entry, to: scope)
        var memory = try load()
        let updated = try memory.changeScope(of: entry, to: scope)
        try save(memory)
        return updated
    }

    func remove(_ entries: [CorrectionExample]) throws {
        var memory = try load()
        try memory.remove(entries)
        try save(memory)
    }

    private func save(_ memory: CorrectionMemory) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(memory).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
