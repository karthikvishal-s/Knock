import AppIntents
import KnockKit

// The capture intents behind Back Tap, Siri, Spotlight, the Action Button and Shortcuts.
// Flow (PLAN.md §3): amount → category → optional note → optional account → save → snippet.
// In "app sheet" capture mode they open the quick-entry sheet instead of prompting.

struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Expense"
    static let description = IntentDescription("Log an expense without opening Knock.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Amount", inclusiveRange: (0.01, 1_000_000_000))
    var amount: Double?

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Note")
    var note: String?

    @Parameter(title: "Account")
    var account: AccountEntity?

    @Parameter(title: "Credit / Refund", default: false)
    var isCredit: Bool

    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) for \(\.$category)") {
            \.$note
            \.$account
            \.$isCredit
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        try await LogFlow.run(
            kind: isCredit ? .refund : .expense,
            amount: $amount, category: $category, note: $note, account: $account, date: date,
            intent: self
        )
    }
}

struct LogIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Income"
    static let description = IntentDescription("Log income without opening Knock.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Amount", inclusiveRange: (0.01, 1_000_000_000))
    var amount: Double?

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Note")
    var note: String?

    @Parameter(title: "Account")
    var account: AccountEntity?

    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) income from \(\.$category)") {
            \.$note
            \.$account
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        try await LogFlow.run(kind: .income, amount: $amount, category: $category, note: $note, account: $account, date: date, intent: self)
    }
}

struct QuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Log"
    static let description = IntentDescription("Log an expense, income or refund — Knock asks which after the amount.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Amount", inclusiveRange: (0.01, 1_000_000_000))
    var amount: Double?

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Note")
    var note: String?

    @Parameter(title: "Account")
    var account: AccountEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        if AppSettings.shared.captureMode == .sheet {
            try await LogFlow.openSheet(.expense, intent: self)
            return .result(dialog: "Opening Knock…", snippetIntent: EmptySnippetIntent())
        }
        let value = try await LogFlow.requestAmount($amount, prompt: "How much?")
        let expense = IntentChoiceOption(title: "Expense")
        let income = IntentChoiceOption(title: "Income")
        let credit = IntentChoiceOption(title: "Credit / refund")
        let choice = try await requestChoice(between: [expense, income, credit], dialog: "What kind?")
        let kind: TransactionKind = choice == income ? .income : choice == credit ? .refund : .expense
        return try await LogFlow.run(kind: kind, presetAmount: value, category: $category, note: $note, account: $account, date: nil, intent: self)
    }
}

enum LogFlowError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount
    case noCategories

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount: "That amount doesn't look right."
        case .noCategories: "Add a category in Knock first."
        }
    }
}

@MainActor
enum LogFlow {
    static func run(
        kind: TransactionKind,
        amount: IntentParameter<Double?>? = nil,
        presetAmount: Decimal? = nil,
        category: IntentParameter<CategoryEntity?>,
        note: IntentParameter<String?>,
        account: IntentParameter<AccountEntity?>,
        date: Date?,
        intent: some AppIntent
    ) async throws -> IntentResultContainer<Never, Never, _SnippetIntentContainer, IntentDialog> {
        let settings = AppSettings.shared
        if settings.captureMode == .sheet, presetAmount == nil, amount?.wrappedValue == nil {
            try await openSheet(kind, intent: intent)
            return .result(dialog: "Opening Knock…", snippetIntent: EmptySnippetIntent())
        }

        // 1. Amount
        let value: Decimal
        if let presetAmount {
            value = presetAmount
        } else if let amount {
            value = try await requestAmount(amount, prompt: kind == .income ? "How much did you receive?" : "How much did you spend?")
        } else {
            throw LogFlowError.invalidAmount
        }

        // 2. Category, likeliest first
        guard let categoryKind = kind.categoryKind else { throw LogFlowError.invalidAmount }
        let chosenCategory: CategoryEntity
        if let preset = category.wrappedValue, preset.kind == categoryKind {
            chosenCategory = preset
        } else {
            let options = try IntentStore.rankedCategories(categoryKind).map(CategoryEntity.init)
            guard !options.isEmpty else { throw LogFlowError.noCategories }
            chosenCategory = try await category.requestDisambiguation(among: options, dialog: "Which category?")
        }

        // 3. Optional note
        var noteText = note.wrappedValue ?? ""
        if noteText.isEmpty, settings.asksNote {
            let add = IntentChoiceOption(title: "Add note")
            let skip = IntentChoiceOption(title: "Skip")
            if try await intent.requestChoice(between: [add, skip], dialog: "Add a note?") == add {
                noteText = try await note.requestValue("What's the note?")
            }
        }

        // 4. Optional account
        var accountID = account.wrappedValue?.id
        if accountID == nil, settings.asksAccount {
            let accounts = try IntentStore.accounts()
            if accounts.count > 1 {
                accountID = try await account.requestDisambiguation(among: accounts.map(AccountEntity.init), dialog: "Which account?").id
            }
        }

        // 5. Save
        let draft = TransactionDraft(
            kind: kind, amount: value, currencyCode: settings.currencyCode,
            categoryID: chosenCategory.id, accountID: accountID, date: date ?? .now, note: noteText, source: .shortcut
        )
        let entry = try IntentStore.service.add(draft)
        let confirmation = IntentStore.confirmation(for: entry)
        return .result(dialog: IntentDialog(stringLiteral: confirmation.spoken), snippetIntent: LoggedSnippetIntent(entryID: entry.id.uuidString))
    }

    static func requestAmount(_ parameter: IntentParameter<Double?>, prompt: IntentDialog) async throws -> Decimal {
        let raw: Double
        if let preset = parameter.wrappedValue {
            raw = preset
        } else {
            raw = try await parameter.requestValue(prompt)
        }
        let digits = CurrencyCatalog.minorUnitDigits(for: AppSettings.shared.currencyCode)
        guard let value = DecimalConversion.decimal(from: raw, fractionDigits: digits), value > 0 else {
            throw LogFlowError.invalidAmount
        }
        return value
    }

    /// App-sheet capture mode: bring Knock forward with the quick-entry sheet open.
    static func openSheet(_ kind: TransactionKind, intent: some AppIntent) async throws {
        try await intent.continueInForeground(nil, alwaysConfirm: false)
        AppRouter.shared.openQuickEntry(kind)
    }
}
