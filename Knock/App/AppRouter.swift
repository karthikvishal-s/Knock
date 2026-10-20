import Observation

enum QuickEntryKind: String, Sendable {
    case expense
    case income
}

/// App-wide navigation state that intents can drive after `continueInForeground`.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var quickEntry: QuickEntryKind?
}
