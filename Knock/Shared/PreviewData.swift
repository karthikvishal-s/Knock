import KnockKit
import SwiftData
import SwiftUI

/// In-memory store with three months of sample data, for `#Preview`s.
enum PreviewData {
    static let container: ModelContainer = {
        do {
            let container = try KnockStore.makeInMemoryContainer()
            try SampleData.populate(context: container.mainContext)
            return container
        } catch {
            fatalError("Preview store failed: \(error)")
        }
    }()

    static let emptyContainer: ModelContainer = {
        do {
            let container = try KnockStore.makeInMemoryContainer()
            try Seeder.seedIfNeeded(context: container.mainContext)
            return container
        } catch {
            fatalError("Preview store failed: \(error)")
        }
    }()

    static var anyEntry: LedgerEntry? {
        var descriptor = FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? container.mainContext.fetch(descriptor).first
    }
}

extension View {
    func previewEnvironment(empty: Bool = false) -> some View {
        modelContainer(empty ? PreviewData.emptyContainer : PreviewData.container)
            .environment(AppRouter())
            .environment(AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard))
            .environment(UndoCenter())
    }
}
