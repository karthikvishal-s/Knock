import AppIntents

/// Transaction kinds as an `AppEnum`, for intent parameters, widgets and controls.
public enum EntryKindAppEnum: String, AppEnum {
    case expense
    case income
    case refund
    case transfer

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transaction Type"
    public static let caseDisplayRepresentations: [EntryKindAppEnum: DisplayRepresentation] = [
        .expense: DisplayRepresentation(title: "Expense", image: .init(systemName: "minus.circle")),
        .income: DisplayRepresentation(title: "Income", image: .init(systemName: "plus.circle")),
        .refund: DisplayRepresentation(title: "Credit / Refund", image: .init(systemName: "arrow.uturn.backward.circle")),
        .transfer: DisplayRepresentation(title: "Transfer", image: .init(systemName: "arrow.left.arrow.right.circle")),
    ]

    public init(_ kind: TransactionKind) {
        self = EntryKindAppEnum(rawValue: kind.rawValue) ?? .expense
    }

    public var kind: TransactionKind { TransactionKind(rawValue: rawValue) ?? .expense }
}

/// The app registers where quick-entry requests go; intents in this package can't see the app.
public enum QuickEntryRouting {
    @MainActor public static var handler: ((TransactionKind) -> Void)?
}

/// Opens Knock's quick-entry sheet. Used by widget buttons and Control Center controls,
/// which can't show the in-place amount/category prompts.
public struct OpenQuickEntryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Quick Entry"
    public static let description = IntentDescription("Opens Knock straight into the keypad.")
    public static let supportedModes: IntentModes = .foreground(.immediate)
    public static let isDiscoverable = false

    @Parameter(title: "Type", default: .expense)
    public var kind: EntryKindAppEnum

    public init() {}

    public init(kind: TransactionKind) {
        self.kind = EntryKindAppEnum(kind)
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        QuickEntryRouting.handler?(kind.kind)
        return .result()
    }
}

/// Lets the app and widget extension include this package's intents in their metadata.
public struct KnockKitIntents: AppIntentsPackage {}
