import Foundation
import KnockKit
import Observation

/// State for the quick-entry sheet. Kind is expense / income / transfer; a credit on an
/// expense turns it into a refund.
@Observable
final class QuickEntryModel {
    var kind: TransactionKind {
        didSet {
            guard kind != oldValue else { return }
            categoryID = nil
            if kind != .expense { isCredit = false }
        }
    }
    var isCredit = false
    var input: AmountInput
    var categoryID: UUID?
    var accountID: UUID?
    var transferAccountID: UUID?
    var note = ""
    var date = Date.now
    let currencyCode: String

    init(kind: TransactionKind, currencyCode: String) {
        self.kind = kind == .refund ? .expense : kind
        self.isCredit = kind == .refund
        self.currencyCode = currencyCode
        self.input = AmountInput(fractionDigits: CurrencyCatalog.minorUnitDigits(for: currencyCode))
    }

    var effectiveKind: TransactionKind { kind == .expense && isCredit ? .refund : kind }

    /// Green when money comes in.
    var isInflow: Bool { effectiveKind == .income || effectiveKind == .refund }

    var amount: Decimal { input.decimal }

    var canSave: Bool {
        guard input.isPositive else { return false }
        if kind == .transfer {
            return accountID != nil && transferAccountID != nil && accountID != transferAccountID
        }
        return categoryID != nil
    }

    /// Why Save is disabled, for the button's accessibility hint.
    var missingRequirement: String? {
        if !input.isPositive { return String(localized: "Enter an amount") }
        if kind == .transfer {
            if accountID == nil || transferAccountID == nil { return String(localized: "Choose both accounts") }
            if accountID == transferAccountID { return String(localized: "Choose two different accounts") }
            return nil
        }
        return categoryID == nil ? String(localized: "Choose a category") : nil
    }

    var draft: TransactionDraft {
        TransactionDraft(
            kind: effectiveKind,
            amount: amount,
            currencyCode: currencyCode,
            categoryID: kind == .transfer ? nil : categoryID,
            accountID: accountID,
            transferAccountID: kind == .transfer ? transferAccountID : nil,
            date: date,
            note: note,
            source: .app
        )
    }

    /// Picks sensible defaults for accounts once they're known.
    func prepare(accounts: [Account]) {
        if accountID == nil {
            accountID = (accounts.first(where: \.isDefault) ?? accounts.first)?.id
        }
        if transferAccountID == nil {
            transferAccountID = accounts.first(where: { $0.id != accountID })?.id
        }
    }
}
