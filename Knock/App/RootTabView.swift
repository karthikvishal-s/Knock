import KnockKit
import SwiftData
import SwiftUI

struct RootTabView: View {
    enum TabID: Hashable {
        case home, history, analytics, budgets, settings
    }

    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var selection: TabID = .home

    var body: some View {
        @Bindable var router = router
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView()
            }
            Tab("History", systemImage: "list.bullet.rectangle.portrait", value: .history) {
                HistoryView()
            }
            Tab("Analytics", systemImage: "chart.pie", value: .analytics) {
                ComingSoonView(title: "Analytics", systemImage: "chart.pie", milestone: "M4")
            }
            Tab("Budgets", systemImage: "gauge.with.dots.needle.50percent", value: .budgets) {
                ComingSoonView(title: "Budgets", systemImage: "gauge.with.dots.needle.50percent", milestone: "M5")
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .fullScreenCover(item: $router.quickEntry) { request in
            QuickEntrySheet(initialKind: request.kind)
        }
        .sheet(item: editingEntry) { entry in
            TransactionEditor(entry: entry)
        }
        .sheet(isPresented: $router.showsBackTapGuide) {
            BackTapGuide { router.showsBackTapGuide = false }
        }
        .fullScreenCover(isPresented: showsOnboarding) {
            WelcomeView { settings.hasCompletedOnboarding = true }
        }
        .overlay(alignment: .top) {
            if let error = AppBootstrap.storeError {
                Label("Data store unavailable — changes won't be saved. \(error)", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .padding(10)
                    .glassEffect(.regular.tint(.red.opacity(0.4)), in: .rect(cornerRadius: 12))
                    .padding()
            }
        }
    }
}

extension RootTabView {
    /// The entry an intent asked to edit, resolved from its ID.
    private var editingEntry: Binding<LedgerEntry?> {
        Binding {
            guard let id = router.editingEntryID else { return nil }
            return try? TransactionService(context: context).entry(id: id)
        } set: { entry in
            router.editingEntryID = entry?.id
        }
    }

    private var showsOnboarding: Binding<Bool> {
        Binding {
            !settings.hasCompletedOnboarding && !AppBootstrap.isUITesting
        } set: { shows in
            if !shows { settings.hasCompletedOnboarding = true }
        }
    }
}

struct ComingSoonView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let milestone: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text("Arrives in milestone \(milestone)."))
                .navigationTitle(title)
        }
    }
}

#Preview {
    RootTabView()
        .previewEnvironment()
}
