import AppIntents
import KnockKit

struct RepeatLastTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Repeat Last Transaction"
    static let description = IntentDescription("Log your most recent expense or income again, dated now.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        guard let last = try IntentStore.service.latestRepeatable() else {
            return .result(dialog: "There's nothing to repeat yet.", snippetIntent: EmptySnippetIntent())
        }
        let preview = IntentStore.confirmation(for: last)
        try await requestConfirmation(actionName: .add, dialog: IntentDialog(stringLiteral: String(localized: "Add \(preview.title) again?")))
        let copy = try IntentStore.service.duplicate(last)
        copy.source = .shortcut
        try IntentStore.context.save()
        return .result(dialog: IntentDialog(stringLiteral: IntentStore.confirmation(for: copy).spoken),
                       snippetIntent: LoggedSnippetIntent(entryID: copy.id.uuidString))
    }
}

struct MonthSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Spending This Month"
    static let description = IntentDescription("Hear how much you've spent and earned this month.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let totals = try IntentStore.currentCycleTotals()
        let code = AppSettings.shared.currencyCode
        let spent = MoneyFormat.string(minor: totals.netSpendMinor, currencyCode: code, showsFraction: false)
        let income = MoneyFormat.string(minor: totals.incomeMinor, currencyCode: code, showsFraction: false)
        var message = String(localized: "You've spent \(spent) this month")
        if totals.incomeMinor > 0 {
            message += String(localized: " and received \(income)")
        }
        if let line = BudgetSnapshotLine.current() {
            message += ". " + line
        }
        return .result(dialog: IntentDialog(stringLiteral: message + "."))
    }
}

/// Optional extra sentence for the month summary; budgets fill this in from M5.
enum BudgetSnapshotLine {
    @MainActor static var provider: (() -> String?)?

    @MainActor static func current() -> String? { provider?() }
}

/// Opens the editor on an entry (the snippet's "Edit" button).
struct OpenEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Transaction"
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let isDiscoverable = false

    @Parameter(title: "Transaction ID")
    var entryID: String

    init() {}

    init(entryID: UUID) {
        self.entryID = entryID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.editingEntryID = UUID(uuidString: entryID)
        return .result()
    }
}

/// The snippet's "Undo" button. Only removes entries created in the last 10 minutes.
struct UndoEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Logged Transaction"
    static let isDiscoverable = false

    @Parameter(title: "Transaction ID")
    var entryID: String

    init() {}

    init(entryID: String) {
        self.entryID = entryID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: entryID) {
            try IntentStore.service.deleteIfRecent(id: id)
        }
        LoggedSnippetIntent.reload()
        return .result()
    }
}
