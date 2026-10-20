import Foundation
import KnockKit
import Observation

/// Period navigation and the current report. Reports are built off-main by `AnalyticsService`.
@Observable
final class AnalyticsModel {
    var kind: Period.Kind = .cycle
    private(set) var period: Period?
    private(set) var report: AnalyticsReport?
    private(set) var isLoading = false
    var errorMessage: String?
    var customRange: (from: Date, through: Date) = (Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now, .now)

    func reset(to kind: Period.Kind, settings: AppSettings) {
        self.kind = kind
        let calc = settings.calculator
        period = kind == .custom ? calc.custom(from: customRange.from, through: customRange.through) : calc.period(kind, containing: .now)
    }

    func shift(_ steps: Int, settings: AppSettings) {
        guard let period else { return }
        self.period = settings.calculator.shifted(period, by: steps)
    }

    func show(_ period: Period) {
        kind = period.kind
        self.period = period
    }

    var canGoForward: Bool {
        guard let period else { return false }
        return period.end <= .now ? true : !period.contains(.now) && period.start < .now
    }

    @MainActor
    func load(settings: AppSettings) async {
        if period == nil { reset(to: kind, settings: settings) }
        guard let period else { return }
        isLoading = report == nil
        do {
            let result = try await AppServices.analytics.report(for: period, calculator: settings.calculator, dataVersion: StoreEvents.dataVersion)
            if result.period == self.period { report = result }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func title(settings: AppSettings) -> String {
        guard let period else { return "" }
        let last = period.end.addingTimeInterval(-1)
        switch period.kind {
        case .year:
            return period.start.formatted(.dateTime.year())
        case .cycle where settings.cycleStartDay == 1:
            return period.start.formatted(.dateTime.month(.wide).year())
        case .week, .cycle, .custom:
            return "\(period.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
    }
}
