import Foundation

/// Where Knock keeps its shared files (SwiftData store, widget snapshot, backups).
///
/// Prefers the App Group container so the app, widgets and controls see the same data.
/// Falls back to the app's own Application Support directory when the App Group isn't
/// provisioned — e.g. a free Personal Team that can't register the group.
public enum StoreLocation {
    public static let appGroupIdentifier = "group.com.karthikvishal.knock"

    public enum Kind: String, Sendable {
        case appGroup
        case appContainer
    }

    public struct Resolved: Sendable {
        public let directory: URL
        public let kind: Kind
    }

    public static func resolve(fileManager: FileManager = .default) -> Resolved {
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return Resolved(directory: group.appending(path: "Library/Application Support", directoryHint: .isDirectory), kind: .appGroup)
        }
        return Resolved(directory: URL.applicationSupportDirectory, kind: .appContainer)
    }

    /// Shared `UserDefaults` for settings that widgets and intents also read.
    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
