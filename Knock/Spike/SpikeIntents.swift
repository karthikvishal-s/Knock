import AppIntents
import KnockKit

// M0 spike intents: verify the decimal prompt, requestChoice, the supportedModes /
// continueInForeground switch, and cold-start time. Replaced by the real intents in M2.

enum SpikeSettings {
    static let openSheetKey = "spike.openSheet"

    static var openSheet: Bool {
        UserDefaults.standard.bool(forKey: openSheetKey)
    }
}

struct SpikeLogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Expense (M0)"
    static let description = IntentDescription("Test intent for the M0 spike.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Amount", requestValueDialog: "How much did you spend?")
    var amount: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let coldStart = LaunchTiming.millisecondsSinceInit()

        if SpikeSettings.openSheet {
            try await continueInForeground(alwaysConfirm: false)
            AppRouter.shared.quickEntry = .expense
            return .result(dialog: "Opening Knock…")
        }

        let kind = try await requestChoice(
            between: [
                IntentChoiceOption(title: "Expense"),
                IntentChoiceOption(title: "Income"),
                IntentChoiceOption(title: "Credit / refund"),
            ],
            dialog: "What kind?"
        )

        guard let value = DecimalConversion.decimal(from: amount, fractionDigits: 2), value > 0 else {
            return .result(dialog: "That amount doesn't look right.")
        }
        let shown = value.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))

        let detail = "\(shown) · \(kind.title.key) · mode \(systemContext.currentMode.debugDescription) · since init \(coldStart.map { "\($0) ms" } ?? "n/a")"
        let previous = SpikeProbe().read(.intentRun)?.counter ?? 0
        try? SpikeProbe().write(ProbeRecord(writer: "intent", counter: previous + 1, detail: detail), to: .intentRun)

        return .result(dialog: "Logged \(shown) (test only — nothing saved)")
    }
}

struct KnockShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SpikeLogExpenseIntent(),
            phrases: [
                "Log expense in \(.applicationName)",
                "Add expense to \(.applicationName)",
            ],
            shortTitle: "Log Expense",
            systemImageName: "minus.circle"
        )
    }
}
