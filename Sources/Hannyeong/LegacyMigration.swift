import Foundation
import os

/// Carries a JevType-era install (before 0.2.0) over to Hannyeong: the data folder and saved preferences.
enum LegacyMigration {
    static let bundleID = "com.yeop.inputmethod.JevType"
    private static let doneKey = "migratedFromJevType"

    static func run() {
        let logger = Logger(subsystem: "com.yeop.inputmethod.Hannyeong", category: "Migration")
        let files = FileManager.default
        let support = files.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let legacyFolder = support.appendingPathComponent("JevType")
        let folder = support.appendingPathComponent("Hannyeong")
        // Merge item by item: something may already have created the new folder, and existing files there win.
        if let items = try? files.contentsOfDirectory(at: legacyFolder, includingPropertiesForKeys: nil) {
            do {
                try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                for item in items where !files.fileExists(atPath: folder.appendingPathComponent(item.lastPathComponent).path) {
                    try files.moveItem(at: item, to: folder.appendingPathComponent(item.lastPathComponent))
                }
                if (try? files.contentsOfDirectory(atPath: legacyFolder.path))?.isEmpty == true {
                    try? files.removeItem(at: legacyFolder)
                }
                logger.notice("Merged the JevType data folder into Hannyeong")
            } catch {
                let failure = error as NSError
                logger.error("Data folder merge failed: \(failure.domain, privacy: .public) code \(failure.code)")
            }
        }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        if let legacy = defaults.persistentDomain(forName: bundleID) {
            for (key, value) in legacy where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            logger.notice("Copied \(legacy.count) JevType preferences")
        }
        defaults.set(true, forKey: doneKey)
    }
}
