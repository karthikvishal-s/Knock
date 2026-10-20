import Foundation
import KnockKit
import Observation
import SwiftData

/// Paged, filtered history. Loads a month at a time; a refresh reloads as deep as the user
/// had scrolled so a change doesn't throw them back to the top.
@Observable
final class HistoryModel {
    var filter = HistoryFilter()
    private(set) var sections: [DaySection] = []
    private(set) var reachedEnd = false
    private(set) var hasLoaded = false
    var errorMessage: String?
    @ObservationIgnored private var cursor: Date?

    var loadedCount: Int { sections.reduce(0) { $0 + $1.entries.count } }

    func reload(context: ModelContext, settings: AppSettings) {
        load(context: context, settings: settings, minimumEntries: max(loadedCount, 30), replacing: true)
    }

    func loadMore(context: ModelContext, settings: AppSettings) {
        guard !reachedEnd else { return }
        load(context: context, settings: settings, minimumEntries: 30, replacing: false)
    }

    private func load(context: ModelContext, settings: AppSettings, minimumEntries: Int, replacing: Bool) {
        let query = HistoryQuery(context: context, calendar: settings.calendar, currencyCode: settings.currencyCode)
        do {
            let page = try query.page(before: replacing ? nil : cursor, filter: filter, minimumEntries: minimumEntries)
            sections = replacing ? page.sections : sections + page.sections
            cursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }
}
