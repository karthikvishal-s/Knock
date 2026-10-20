import KnockKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(UndoCenter.self) private var undoCenter

    @State private var model = HistoryModel()
    @State private var editing: LedgerEntry?
    @State private var showsFilters = false
    @State private var lastSearch = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("History")
                .searchable(text: $model.filter.searchText, prompt: "Note, payee or amount")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsFilters = true
                        } label: {
                            Label("Filters", systemImage: model.filter.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        .badge(model.filter.activeCount)
                        .accessibilityIdentifier("filter-button")
                    }
                }
                .task(id: model.filter) {
                    // Debounce typing; other filter changes apply immediately.
                    if model.filter.searchText != lastSearch {
                        lastSearch = model.filter.searchText
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                    }
                    model.reload(context: context, settings: settings)
                }
                .onReceive(NotificationCenter.default.publisher(for: StoreEvents.didChange)) { _ in
                    model.reload(context: context, settings: settings)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    model.reload(context: context, settings: settings)
                }
                .sheet(item: $editing) { entry in
                    TransactionEditor(entry: entry)
                }
                .sheet(isPresented: $showsFilters) {
                    FilterSheet(filter: $model.filter)
                }
                .floatingAddButton()
                .undoToast()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.hasLoaded, model.sections.isEmpty {
            if model.filter.isActive {
                ContentUnavailableView {
                    Label("No matches", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search or clear the filters.")
                } actions: {
                    Button("Clear filters") { model.filter = HistoryFilter() }
                        .buttonStyle(.glass)
                }
            } else {
                ContentUnavailableView("No transactions yet", systemImage: "tray", description: Text("Tap + to log your first expense."))
            }
        } else {
            List {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            Button {
                                editing = entry
                            } label: {
                                EntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                                Button("Edit", systemImage: "pencil") { editing = entry }
                                    .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(entry) }
                                    .tint(.indigo)
                            }
                        }
                    } header: {
                        DayHeader(date: section.date, totals: section.totals, currencyCode: settings.currencyCode)
                    }
                }
                if !model.reachedEnd {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .onAppear { model.loadMore(context: context, settings: settings) }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("history-list")
        }
    }

    private var service: TransactionService {
        TransactionService(context: context, calculator: settings.calculator)
    }

    private func delete(_ entry: LedgerEntry) {
        let message = deleteMessage(for: entry)
        do {
            let deleted = try service.delete(entry)
            undoCenter.offer(deleted, message: message)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func duplicate(_ entry: LedgerEntry) {
        do {
            try service.duplicate(entry)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

struct DayHeader: View {
    let date: Date
    let totals: Totals
    let currencyCode: String

    var body: some View {
        HStack {
            Text(dayTitle)
            Spacer()
            if totals.netSpendMinor != 0 {
                Text(MoneyFormat.string(minor: -totals.netSpendMinor, currencyCode: currencyCode, sign: .explicit))
                    .monospacedDigit()
            }
            if totals.incomeMinor > 0 {
                Text(MoneyFormat.string(minor: totals.incomeMinor, currencyCode: currencyCode, sign: .explicit))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }
        }
        .font(.footnote.weight(.semibold))
    }

    private var dayTitle: String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }
}

#Preview {
    HistoryView()
        .previewEnvironment()
}

#Preview("Empty") {
    HistoryView()
        .previewEnvironment(empty: true)
}
