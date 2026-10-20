import Foundation
import KnockKit
import Observation

/// A request to open the quick-entry sheet, from the "+" button or an intent.
struct QuickEntryRequest: Identifiable, Equatable {
    let id = UUID()
    var kind: TransactionKind
}

/// App-wide navigation state that intents can drive after `continueInForeground`.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var quickEntry: QuickEntryRequest?
    /// An entry to open in the editor (from a confirmation snippet's "Edit").
    var editingEntryID: UUID?
    var showsBackTapGuide = false

    func openQuickEntry(_ kind: TransactionKind = .expense) {
        quickEntry = QuickEntryRequest(kind: kind)
    }
}
