import KnockKit
import Observation
import SwiftData
import SwiftUI

/// Holds the most recent delete for a few seconds so it can be undone from a toast.
@Observable
final class UndoCenter {
    struct Item: Identifiable {
        let id = UUID()
        let message: String
        let deleted: DeletedEntry
    }

    private(set) var current: Item?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func offer(_ deleted: DeletedEntry, message: String) {
        let item = Item(message: message, deleted: deleted)
        current = item
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self?.current?.id == item.id else { return }
            self?.current = nil
        }
    }

    func undo(using service: TransactionService) throws {
        guard let item = current else { return }
        current = nil
        dismissTask?.cancel()
        try service.restore(item.deleted)
    }

    func dismiss() {
        current = nil
        dismissTask?.cancel()
    }
}

/// Shows the undo toast above the tab bar.
struct UndoToastModifier: ViewModifier {
    @Environment(UndoCenter.self) private var undoCenter
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let item = undoCenter.current {
                    HStack {
                        Text(item.message)
                            .font(.subheadline)
                            .lineLimit(2)
                        Spacer()
                        Button("Undo") {
                            do {
                                try undoCenter.undo(using: TransactionService(context: context, calculator: settings.calculator))
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("undo-button")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: undoCenter.current?.id)
            .alert("Couldn't undo", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

extension View {
    func undoToast() -> some View { modifier(UndoToastModifier()) }
}
