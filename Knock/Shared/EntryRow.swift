import KnockKit
import SwiftUI

/// One ledger entry in a list: category badge, title, details, signed amount.
struct EntryRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(emoji: badgeEmoji, colorHex: entry.category?.colorHex ?? "#8E8E93")
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        // The whole row is tappable, including the gap between title and amount.
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var badgeEmoji: String {
        entry.kind == .transfer ? "⇄" : entry.category?.emoji ?? "🏷️"
    }

    private var title: String {
        if !entry.payee.isEmpty { return entry.payee }
        if entry.kind == .transfer { return String(localized: "Transfer") }
        return entry.category?.name ?? String(localized: "Uncategorised")
    }

    private var subtitle: String {
        var parts: [String] = []
        if !entry.payee.isEmpty, let name = entry.category?.name { parts.append(name) }
        if entry.kind == .refund { parts.append(String(localized: "Refund")) }
        if !entry.note.isEmpty { parts.append(entry.note) }
        if entry.kind == .transfer {
            parts.append("\(entry.account?.name ?? "?") → \(entry.transferAccount?.name ?? "?")")
        } else if let account = entry.account?.name {
            parts.append(account)
        }
        return parts.joined(separator: " · ")
    }

    private var amountText: String {
        let sign: MoneyFormat.Sign = entry.kind == .transfer ? .none : .explicit
        return MoneyFormat.string(minor: entry.kind == .transfer ? entry.amountMinor : entry.cashFlowMinor, currencyCode: entry.currencyCode, sign: sign)
    }

    private var amountColor: Color {
        switch entry.kind {
        case .expense: .primary
        case .income, .refund: .green
        case .transfer: .secondary
        }
    }

    private var accessibilityText: String {
        [title, subtitle, amountText, entry.date.formatted(date: .abbreviated, time: .shortened)]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

struct CategoryBadge: View {
    let emoji: String
    let colorHex: String
    var size: CGFloat = 38

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Color(hex: colorHex).opacity(0.22), in: .circle)
            .accessibilityHidden(true)
    }
}
