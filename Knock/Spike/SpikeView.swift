import AppIntents
import KnockKit
import SwiftUI
import WidgetKit

/// M0 diagnostics screen. Replaced by the real Home in M1.
struct SpikeView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(SpikeSettings.openSheetKey) private var openSheet = false
    @State private var location = StoreLocation.resolve()
    @State private var appWrite: ProbeRecord?
    @State private var widgetAck: ProbeRecord?
    @State private var intentRun: ProbeRecord?
    @State private var errorText: String?

    private let probe = SpikeProbe()

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            List {
                Section {
                    LabeledContent("Container", value: location.kind == .appGroup ? "App Group ✓" : "App only ✗")
                    Text(location.directory.path(percentEncoded: false))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text("1 · Shared storage")
                }

                Section {
                    Button("Write probe & reload widgets", action: writeProbe)
                    recordRow("App wrote", appWrite)
                    recordRow("Widget read", widgetAck)
                } header: {
                    Text("2 · App ↔ widget round trip")
                } footer: {
                    Text("Add the “Knock M0” widget to your Home Screen, tap Write, then come back. If “Widget read” shows the same counter, App Groups work on your account.")
                }

                Section {
                    Toggle("Open app sheet instead of in-place", isOn: $openSheet)
                    recordRow("Last intent run", intentRun)
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)
                } header: {
                    Text("3 · App Intents")
                } footer: {
                    Text("Run “Log Expense (M0)” from Shortcuts or Siri (“Log expense in Knock”), with the app closed. The run records the decimal it parsed, the mode it ran in, and the cold-start time.")
                }

                if let errorText {
                    Section("Error") {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Knock · M0 checks")
            .refreshable(action: reload)
            .task { reload() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                reload()
            }
            .fullScreenCover(item: $router.quickEntry) { kind in
                SpikeQuickEntrySheet(kind: kind)
            }
        }
    }

    private func recordRow(_ title: String, _ record: ProbeRecord?) -> some View {
        LabeledContent(title) {
            if let record {
                VStack(alignment: .trailing) {
                    Text("#\(record.counter) · \(record.writtenAt.formatted(date: .omitted, time: .standard))")
                    if !record.detail.isEmpty {
                        Text(record.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("—")
            }
        }
    }

    private func writeProbe() {
        let record = ProbeRecord(writer: "app", counter: (appWrite?.counter ?? 0) + 1)
        do {
            try probe.write(record, to: .appWrite)
            WidgetCenter.shared.reloadAllTimelines()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        reload()
    }

    private func reload() {
        location = StoreLocation.resolve()
        appWrite = probe.read(.appWrite)
        widgetAck = probe.read(.widgetAck)
        intentRun = probe.read(.intentRun)
    }
}

extension QuickEntryKind: Identifiable {
    var id: String { rawValue }
}

private struct SpikeQuickEntrySheet: View {
    let kind: QuickEntryKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Quick entry (\(kind.rawValue))",
                systemImage: "keyboard",
                description: Text("An intent opened the app in sheet mode. The real keypad sheet arrives in M1.")
            )
            .toolbar {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
        }
    }
}

#Preview {
    SpikeView()
        .environment(AppRouter())
}
