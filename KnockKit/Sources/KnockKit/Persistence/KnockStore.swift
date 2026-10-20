import Foundation
import SwiftData

public enum KnockStore {
    public static let fileName = "Knock.store"

    public static var schema: Schema { Schema(versionedSchema: SchemaV1.self) }

    /// The on-disk store in the shared container (App Group when available).
    public static func makeContainer(directory: URL = StoreLocation.resolve().directory) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            "Knock",
            schema: schema,
            url: directory.appending(path: fileName),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: KnockMigrationPlan.self, configurations: configuration)
    }

    /// A throwaway store for tests, previews and UI tests.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration("KnockMemory", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: KnockMigrationPlan.self, configurations: configuration)
    }
}

/// Signals that ledger data changed, so screens holding fetched (non-`@Query`) results reload
/// and widget/analytics caches know they're stale.
public enum StoreEvents {
    public static let didChange = Notification.Name("KnockStoreDidChange")
    private static let versionKey = "store.dataVersion"

    public static var dataVersion: Int { StoreLocation.sharedDefaults.integer(forKey: versionKey) }

    public static func bump() {
        let defaults = StoreLocation.sharedDefaults
        defaults.set(defaults.integer(forKey: versionKey) &+ 1, forKey: versionKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
