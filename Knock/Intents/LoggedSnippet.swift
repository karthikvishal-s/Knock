import AppIntents
import KnockKit
import SwiftUI

/// The interactive confirmation card shown after a quick log: amount · category, month total,
/// and Undo / Edit buttons. Re-renders (via `reload()`) after Undo.
struct LoggedSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Logged Transaction"
    static let isDiscoverable = false

    @Parameter(title: "Transaction ID")
    var entryID: String

    init() {}

    init(entryID: String) {
        self.entryID = entryID
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard let id = UUID(uuidString: entryID), let entry = try IntentStore.service.entry(id: id) else {
            return .result(view: LoggedSnippetView(state: .removed))
        }
        let canUndo = Date.now.timeIntervalSince(entry.createdAt) <= 600
        return .result(view: LoggedSnippetView(state: .logged(IntentStore.confirmation(for: entry), entryID: entryID, canUndo: canUndo)))
    }
}

struct LoggedSnippetView: View {
    enum State {
        case logged(LogConfirmation, entryID: String, canUndo: Bool)
        case removed
    }

    let state: State

    var body: some View {
        switch state {
        case .removed:
            Label("Removed", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        case let .logged(confirmation, entryID, canUndo):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(confirmation.title)
                            .font(.headline)
                            .foregroundStyle(confirmation.isInflow ? .green : .primary)
                            .monospacedDigit()
                        if let subtitle = confirmation.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                HStack {
                    if canUndo {
                        Button(intent: UndoEntryIntent(entryID: entryID)) {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                    }
                    if let id = UUID(uuidString: entryID) {
                        Button(intent: OpenEntryIntent(entryID: id)) {
                            Label("Edit", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
