import AppIntents
import KnockKit
import SwiftUI
import WidgetKit

/// M0 diagnostics, reachable from Settings → Developer. Removed once M2/M6 replace the spikes.
struct SpikeView: View {
    @AppStorage(SpikeSettings.openSheetKey) private var openSheet = false
    @State private var location = StoreLocation.resolve()
    @State private var appWrite: ProbeRecord?
    @State private var widgetAck: ProbeRecord?
    @State private var intentRun: ProbeRecord?
    @State private var errorText: String?

    private let probe = SpikeProbe()

    var body: some View {
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
        .navigationTitle("M0 checks")
        .refreshable(action: reload)
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            reload()
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

#Preview {
    NavigationStack {
        SpikeView()
    }
}
