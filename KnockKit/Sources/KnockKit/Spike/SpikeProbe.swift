import Foundation

// M0 spike only — proves the app and widget extension can exchange files through the
// App Group, and records App Intent runs. Delete this folder once M0 is signed off.

public struct ProbeRecord: Codable, Sendable, Equatable {
    public var writer: String
    public var counter: Int
    public var writtenAt: Date
    public var detail: String

    public init(writer: String, counter: Int, writtenAt: Date = .now, detail: String = "") {
        self.writer = writer
        self.counter = counter
        self.writtenAt = writtenAt
        self.detail = detail
    }
}

public struct SpikeProbe: Sendable {
    public enum Slot: String, Sendable, CaseIterable {
        case appWrite = "probe-app.json"
        case widgetAck = "probe-widget.json"
        case intentRun = "probe-intent.json"
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public init() {
        self.init(directory: StoreLocation.resolve().directory)
    }

    public func write(_ record: ProbeRecord, to slot: Slot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.probe.encode(record)
        try data.write(to: directory.appending(path: slot.rawValue), options: .atomic)
    }

    public func read(_ slot: Slot) -> ProbeRecord? {
        guard let data = try? Data(contentsOf: directory.appending(path: slot.rawValue)) else { return nil }
        return try? JSONDecoder.probe.decode(ProbeRecord.self, from: data)
    }
}

private extension JSONEncoder {
    static var probe: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var probe: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
