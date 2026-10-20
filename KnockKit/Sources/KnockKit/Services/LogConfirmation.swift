import Foundation

/// The text a quick-log confirmation shows, e.g. "₹250.00 · 🍔 Food" / "₹4,320 spent this month".
public struct LogConfirmation: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let isInflow: Bool
    /// What Siri reads aloud.
    public let spoken: String

    public init(kind: TransactionKind, amountMinor: Int64, currencyCode: String, categoryName: String?, categoryEmoji: String?,
                cycleTotals: Totals?, locale: Locale = .autoupdatingCurrent) {
        let amount = MoneyFormat.string(minor: amountMinor, currencyCode: currencyCode, locale: locale)
        let label = [categoryEmoji, categoryName].compactMap { $0 }.joined(separator: " ")
        isInflow = kind == .income || kind == .refund

        switch kind {
        case .refund:
            title = label.isEmpty ? "+\(amount) refund" : "+\(amount) refund · \(label)"
        case .income:
            title = label.isEmpty ? "+\(amount)" : "+\(amount) · \(label)"
        case .expense, .transfer:
            title = label.isEmpty ? amount : "\(amount) · \(label)"
        }

        if let cycleTotals {
            if kind == .income {
                let income = MoneyFormat.string(minor: cycleTotals.incomeMinor, currencyCode: currencyCode, locale: locale, showsFraction: false)
                subtitle = String(localized: "\(income) income this month")
            } else {
                let spent = MoneyFormat.string(minor: cycleTotals.netSpendMinor, currencyCode: currencyCode, locale: locale, showsFraction: false)
                subtitle = String(localized: "\(spent) spent this month")
            }
        } else {
            subtitle = nil
        }

        let name = categoryName ?? ""
        switch kind {
        case .income: spoken = name.isEmpty ? String(localized: "Added \(amount) income.") : String(localized: "Added \(amount) income from \(name).")
        case .refund: spoken = name.isEmpty ? String(localized: "Added a \(amount) refund.") : String(localized: "Added a \(amount) refund to \(name).")
        case .expense, .transfer: spoken = name.isEmpty ? String(localized: "Logged \(amount).") : String(localized: "Logged \(amount) for \(name).")
        }
    }
}
