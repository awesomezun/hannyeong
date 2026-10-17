import Foundation

enum CompositionPreviewSettings {
    static let defaultKey = "composition.previewEnglish"
    static let applicationsKey = "composition.previewByBundleID"
    static let alternateEnabledKey = "composition.alternatePreviewEnabled"

    static func alternateEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: alternateEnabledKey) as? Bool ?? true
    }

    static func applications(in defaults: UserDefaults) -> [String: Bool] {
        defaults.dictionary(forKey: applicationsKey) as? [String: Bool] ?? [:]
    }

    static func english(for bundleID: String?, in defaults: UserDefaults) -> Bool {
        if let bundleID, let english = applications(in: defaults)[bundleID] { return english }
        return defaults.bool(forKey: defaultKey)
    }

    static func set(_ english: Bool?, for bundleID: String, in defaults: UserDefaults) {
        var applications = applications(in: defaults)
        applications[bundleID] = english
        defaults.set(applications, forKey: applicationsKey)
    }
}
