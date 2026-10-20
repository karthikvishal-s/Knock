import Foundation
import Testing
@testable import KnockKit

struct SpikeProbeTests {
    @Test func roundTripsEachSlot() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = SpikeProbe(directory: directory)

        for (index, slot) in SpikeProbe.Slot.allCases.enumerated() {
            let record = ProbeRecord(writer: slot.rawValue, counter: index, writtenAt: Date(timeIntervalSince1970: 1_800_000_000), detail: "x")
            try probe.write(record, to: slot)
            #expect(probe.read(slot) == record)
        }
    }

    @Test func missingSlotReadsNil() {
        let probe = SpikeProbe(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        #expect(probe.read(.widgetAck) == nil)
    }
}
