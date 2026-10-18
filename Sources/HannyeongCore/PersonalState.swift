import Foundation

/// Where the local worker keeps its personal correction weights.
///
/// The weights live in one selector's score space, so each selector model gets its own file
/// (`local-b3-session-personal-<first 12 of modelID>.json`). Files that belong to other models are
/// kept untouched and never applied. The pre-0.2.1 file without a model suffix is renamed once to the
/// name of the model it records; its contents are not changed.
public struct PersonalStateSelection: Sendable, Equatable {
    public enum Origin: Sendable, Equatable {
        /// A file for the current model already existed.
        case existing
        /// No file for the current model existed; the worker starts with no personal weights.
        case new
    }

    public let modelID: String
    public let url: URL
    public let origin: Origin
    /// The legacy file was renamed to this per-model file during this selection.
    public let migratedLegacy: URL?
    /// Personal files of other models, kept in place and not applied (sorted by name).
    public let otherModelFiles: [URL]
}

public enum PersonalState {
    public static let prefix = "local-b3-session-personal"
    public static var legacyName: String { prefix + ".json" }

    public static func fileName(for modelID: String) -> String {
        "\(prefix)-\(modelID.prefix(12)).json"
    }

    /// The selector's modelID, read from the same `model.json` the worker loads.
    public static func modelID(ofModel model: URL) throws -> String {
        try storedModelID(at: model.appendingPathComponent("model.json"), kind: "Local model")
    }

    public static func select(directory: URL, modelID: String,
                              fileManager: FileManager = .default) throws -> PersonalStateSelection {
        guard modelID.count >= 12 else {
            throw LocalDecisionError(detail: "Local model ID is too short: \(modelID)")
        }
        var migrated: URL?
        let legacy = directory.appendingPathComponent(legacyName)
        if fileManager.fileExists(atPath: legacy.path) {
            let owner = try storedModelID(at: legacy, kind: "Personal state")
            let destination = directory.appendingPathComponent(fileName(for: owner))
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw LocalDecisionError(detail:
                    "Both \(legacyName) and \(destination.lastPathComponent) exist for model \(owner); resolve them manually")
            }
            try fileManager.moveItem(at: legacy, to: destination)
            migrated = destination
        }
        let url = directory.appendingPathComponent(fileName(for: modelID))
        let origin: PersonalStateSelection.Origin
        if fileManager.fileExists(atPath: url.path) {
            let owner = try storedModelID(at: url, kind: "Personal state")
            guard owner == modelID else {
                throw LocalDecisionError(detail:
                    "\(url.lastPathComponent) belongs to model \(owner), not \(modelID)")
            }
            origin = .existing
        } else {
            origin = .new
        }
        let names = fileManager.fileExists(atPath: directory.path)
            ? try fileManager.contentsOfDirectory(atPath: directory.path) : []
        let others = names
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") && $0 != url.lastPathComponent }
            .sorted()
            .map { directory.appendingPathComponent($0) }
        return PersonalStateSelection(modelID: modelID, url: url, origin: origin,
                                      migratedLegacy: migrated, otherModelFiles: others)
    }

    private struct Stored: Decodable { let modelID: String }

    private static func storedModelID(at url: URL, kind: String) throws -> String {
        do {
            return try JSONDecoder().decode(Stored.self, from: Data(contentsOf: url)).modelID
        } catch {
            throw LocalDecisionError(detail: "\(kind) \(url.lastPathComponent) has no readable modelID: \(error)")
        }
    }
}
