import KnockKit
import SwiftUI

/// The glass "+" in the bottom-right corner. Tap logs an expense; long-press picks the type.
struct FloatingAddButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Menu {
            Button("Expense", systemImage: "minus.circle") { router.openQuickEntry(.expense) }
            Button("Income", systemImage: "plus.circle") { router.openQuickEntry(.income) }
            Button("Transfer", systemImage: "arrow.left.arrow.right.circle") { router.openQuickEntry(.transfer) }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 60, height: 60)
                .contentShape(.circle)
        } primaryAction: {
            router.openQuickEntry(.expense)
        }
        .glassEffect(.regular.tint(.accentColor.opacity(0.35)).interactive(), in: .circle)
        .padding(.trailing, 20)
        .padding(.bottom, 12)
        .accessibilityLabel("Add transaction")
        .accessibilityHint("Long-press to choose expense, income or transfer")
        .accessibilityIdentifier("add-button")
    }
}

extension View {
    func floatingAddButton() -> some View {
        overlay(alignment: .bottomTrailing) { FloatingAddButton() }
    }
}
