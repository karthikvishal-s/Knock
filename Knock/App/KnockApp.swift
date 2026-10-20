import KnockKit
import SwiftData
import SwiftUI

@main
struct KnockApp: App {
    @State private var router = AppRouter.shared
    @State private var settings = AppSettings.shared
    @State private var undoCenter = UndoCenter()
    @State private var lock = AppLock(settings: .shared)
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LaunchTiming.markAppInit()
        QuickEntryRouting.handler = { kind in AppRouter.shared.openQuickEntry(kind) }
        AppCoordinator.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(router)
                .environment(settings)
                .environment(undoCenter)
                .modifier(LockGate(lock: lock))
        }
        .modelContainer(AppBootstrap.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: AppCoordinator.shared.appBecameActive()
            case .background: AppCoordinator.shared.scheduleBackgroundRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AppCoordinator.refreshTaskID)) {
            await AppCoordinator.shared.handleBackgroundRefresh()
        }
    }
}

/// Builds the one `ModelContainer` the app and its intents share.
enum AppBootstrap {
    /// Set when the on-disk store couldn't open and the app fell back to memory.
    private(set) static var storeError: String?

    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")

    static let container: ModelContainer = {
        do {
            let container = isUITesting ? try KnockStore.makeInMemoryContainer() : try KnockStore.makeContainer()
            try Seeder.seedIfNeeded(context: container.mainContext, currencyCode: AppSettings.shared.currencyCode)
            if isUITesting, ProcessInfo.processInfo.arguments.contains("-sample-data") {
                try SampleData.populate(context: container.mainContext)
            }
            return container
        } catch {
            storeError = error.localizedDescription
            do {
                let fallback = try KnockStore.makeInMemoryContainer()
                try? Seeder.seedIfNeeded(context: fallback.mainContext)
                return fallback
            } catch {
                fatalError("Knock can't create any data store: \(error)")
            }
        }
    }()
}
