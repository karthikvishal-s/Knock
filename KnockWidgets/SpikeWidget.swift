import KnockKit
import SwiftUI
import WidgetKit

// M0 spike: reads the app's probe from the App Group and writes an acknowledgement back,
// proving both directions of the shared container. Replaced by real widgets in M6.

struct SpikeEntry: TimelineEntry {
    let date: Date
    let kind: StoreLocation.Kind
    let appWrite: ProbeRecord?
}

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry {
        SpikeEntry(date: .now, kind: .appGroup, appWrite: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
        completion(makeEntry(acknowledge: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        completion(Timeline(entries: [makeEntry(acknowledge: true)], policy: .never))
    }

    private func makeEntry(acknowledge: Bool) -> SpikeEntry {
        let location = StoreLocation.resolve()
        let probe = SpikeProbe(directory: location.directory)
        let appWrite = probe.read(.appWrite)
        if acknowledge, let appWrite {
            try? probe.write(ProbeRecord(writer: "widget", counter: appWrite.counter, detail: "widget saw app #\(appWrite.counter)"), to: .widgetAck)
        }
        return SpikeEntry(date: .now, kind: location.kind, appWrite: appWrite)
    }
}

struct SpikeWidgetView: View {
    let entry: SpikeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Knock M0").font(.headline)
            Label(entry.kind == .appGroup ? "App Group" : "No group", systemImage: entry.kind == .appGroup ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(entry.kind == .appGroup ? .green : .red)
            Spacer(minLength: 0)
            if let write = entry.appWrite {
                Text("Read #\(write.counter)").font(.title2.bold())
                Text(write.writtenAt, style: .time).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("No probe yet").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SpikeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpikeWidget", provider: SpikeProvider()) { entry in
            SpikeWidgetView(entry: entry)
        }
        .configurationDisplayName("Knock M0")
        .description("App Group round-trip test.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    SpikeWidget()
} timeline: {
    SpikeEntry(date: .now, kind: .appGroup, appWrite: ProbeRecord(writer: "app", counter: 3))
    SpikeEntry(date: .now, kind: .appContainer, appWrite: nil)
}
