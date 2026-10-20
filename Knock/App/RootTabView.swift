import KnockKit
import SwiftUI

struct RootTabView: View {
    enum TabID: Hashable {
        case home, history, analytics, budgets, settings
    }

    @Environment(AppRouter.self) private var router
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
