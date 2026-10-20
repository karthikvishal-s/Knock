import AppIntents
import KnockKit

/// App Shortcuts: available in Siri, Spotlight, the Shortcuts app and the Action Button
/// with no setup. Back Tap needs one of these saved to the Shortcuts library (see the guide).
struct KnockShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log expense in \(.applicationName)",
                "Add expense to \(.applicationName)",
                "\(.applicationName) expense",
            ],
            shortTitle: "Log Expense",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: LogIncomeIntent(),
            phrases: [
                "Add income in \(.applicationName)",
                "Log income in \(.applicationName)",
                "\(.applicationName) income",
            ],
            shortTitle: "Log Income",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: QuickLogIntent(),
            phrases: ["Quick log in \(.applicationName)"],
            shortTitle: "Quick Log",
            systemImageName: "bolt.circle"
        )
        AppShortcut(
            intent: RepeatLastTransactionIntent(),
            phrases: [
                "Repeat last in \(.applicationName)",
                "Log that again in \(.applicationName)",
            ],
            shortTitle: "Repeat Last",
            systemImageName: "arrow.clockwise.circle"
        )
        AppShortcut(
            intent: MonthSummaryIntent(),
            phrases: [
                "How much did I spend in \(.applicationName)",
                "\(.applicationName) summary",
            ],
            shortTitle: "This Month",
            systemImageName: "chart.pie"
        )
    }
}

/// Pulls in intents defined in KnockKit (e.g. `OpenQuickEntryIntent`).
struct KnockAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [KnockKitIntents.self] }
}
