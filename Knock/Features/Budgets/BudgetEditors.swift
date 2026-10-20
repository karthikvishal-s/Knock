import KnockKit
import SwiftData
import SwiftUI

struct BudgetEditor: View {
    enum Target: Identifiable, Hashable {
        case overall
        case newCategory
        case category(UUID?)
        case rule
        case goal

        var id: String {
            switch self {
            case .overall: "overall"
            case .newCategory: "new"
            case .category(let id): "category-\(id?.uuidString ?? "")"
            case .rule: "rule"
            case .goal: "goal"
            }
        }
    }

    let target: Target

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<LedgerCategory> { !$0.isArchived }, sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var categoryID: UUID?
    @State private var limit: Decimal?
    @State private var rollover = false
    @State private var thresholds: Set<Int> = [50, 80, 100]
    @State private var existing: Budget?
    @State private var errorMessage: String?

    private var service: BudgetService { BudgetService(context: context, calculator: settings.calculator) }
    private var isOverall: Bool { target == .overall }

    var body: some View {
        NavigationStack {
            Form {
                if !isOverall {
                    Picker("Category", selection: $categoryID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(categories.filter { $0.kind == .expense && $0.parent == nil }) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    .onChange(of: categoryID) { loadExisting() }
                }
                Section {
                    TextField("Amount per cycle", value: $limit, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                    Toggle("Roll over unspent", isOn: $rollover)
                } footer: {
                    Text(isOverall ? "Covers all spending in each cycle (starts on day \(settings.cycleStartDay))." : "Includes this category's sub-categories.")
                }
                Section("Alert me at") {
                    ForEach([50, 80, 100], id: \.self) { value in
                        Toggle("\(value)% used", isOn: Binding {
                            thresholds.contains(value)
                        } set: { on in
                            if on { thresholds.insert(value) } else { thresholds.remove(value) }
                        })
                    }
                }
                if let existing {
                    Section {
                        Button("Remove budget", systemImage: "trash", role: .destructive) {
                            perform { try service.delete(existing) }
                        }
                    }
                }
            }
            .navigationTitle(isOverall ? "Monthly Budget" : "Category Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        perform {
                            try service.setBudget(categoryID: isOverall ? nil : categoryID, limit: limit ?? 0, currencyCode: settings.currencyCode,
                                                  rollover: rollover, thresholds: Array(thresholds))
                        }
                        Task { _ = await NotificationScheduler.shared.requestAuthorization() }
                    }
                    .disabled((limit ?? 0) <= 0 || (!isOverall && categoryID == nil))
                }
            }
            .onAppear {
                if case .category(let id) = target { categoryID = id }
                loadExisting()
            }
            .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func loadExisting() {
        let wanted = isOverall ? nil : categoryID
        existing = try? service.activeBudgets().first { $0.category?.id == wanted && (isOverall || wanted != nil) }
        if let existing {
            limit = Money(minorUnits: existing.limitMinor, currencyCode: settings.currencyCode).amount
            rollover = existing.rollover
            thresholds = Set(existing.alertThresholds)
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Recurring

struct RecurringListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \RecurringRule.nextDueDate) private var rules: [RecurringRule]
    @State private var editing: RecurringRule?
    @State private var adds = false

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView("No recurring transactions", systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("Add rent, salary, subscriptions or EMIs once and Knock logs or reminds you each time."))
            }
            ForEach(rules) { rule in
                Button { editing = rule } label: {
                    HStack(spacing: 12) {
                        Text(rule.category?.emoji ?? (rule.kind == .transfer ? "⇄" : "🔁")).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.displayName)
                            Text(summary(rule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(MoneyFormat.string(minor: rule.amountMinor, currencyCode: rule.currencyCode, showsFraction: false))
                            .monospacedDigit()
                            .foregroundStyle(rule.kind == .income ? .green : .primary)
                    }
                    .opacity(rule.isActive ? 1 : 0.5)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        try? RecurringService(context: context, calculator: settings.calculator).delete(rule)
                    }
                    if rule.isActive {
                        Button("Skip next", systemImage: "forward") {
                            try? RecurringService(context: context, calculator: settings.calculator).skip(rule)
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .navigationTitle("Recurring")
        .toolbar { Button("Add", systemImage: "plus") { adds = true } }
        .sheet(isPresented: $adds) { RuleEditor(rule: nil) }
        .sheet(item: $editing) { RuleEditor(rule: $0) }
    }

    private func summary(_ rule: RecurringRule) -> String {
        let every: String
        switch (rule.frequency, rule.interval) {
        case (.daily, 1): every = String(localized: "Daily")
        case (.weekly, 1): every = String(localized: "Weekly")
        case (.monthly, 1): every = String(localized: "Monthly")
        case (.yearly, 1): every = String(localized: "Yearly")
        case (.daily, let n): every = String(localized: "Every \(n) days")
        case (.weekly, let n): every = String(localized: "Every \(n) weeks")
        case (.monthly, let n): every = String(localized: "Every \(n) months")
        case (.yearly, let n): every = String(localized: "Every \(n) years")
        }
        let mode = rule.mode == .autoPost ? String(localized: "auto-logs") : String(localized: "reminds")
        return rule.isActive ? "\(every) · next \(rule.nextDueDate.formatted(.dateTime.day().month())) · \(mode)" : String(localized: "\(every) · ended")
    }
}

struct RuleEditor: View {
    let rule: RecurringRule?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<LedgerCategory> { !$0.isArchived }, sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder) private var accounts: [Account]

    @State private var draft: RecurringDraft
    @State private var amount: Decimal?
    @State private var hasEnd: Bool
    @State private var errorMessage: String?

    init(rule: RecurringRule?) {
        self.rule = rule
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        let draft = rule.map(RecurringDraft.init(rule:)) ?? RecurringDraft(spec: RecurrenceSpec(frequency: .monthly, startDate: start))
        _draft = State(initialValue: draft)
        _amount = State(initialValue: rule == nil ? nil : draft.amount)
        _hasEnd = State(initialValue: draft.spec.endDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $draft.kind) {
                        Text("Expense").tag(TransactionKind.expense)
                        Text("Income").tag(TransactionKind.income)
                        Text("Transfer").tag(TransactionKind.transfer)
                    }
                    .pickerStyle(.segmented)
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                    TextField("Name (e.g. Rent, Netflix, Salary)", text: $draft.payee)
                }
                Section {
                    if draft.kind == .transfer {
                        accountPicker("From", $draft.accountID)
                        accountPicker("To", $draft.transferAccountID)
                    } else {
                        Picker("Category", selection: $draft.categoryID) {
                            Text("None").tag(UUID?.none)
                            ForEach(categories.filter { $0.kind == draft.kind.categoryKind }) { Text($0.displayName).tag(Optional($0.id)) }
                        }
                        accountPicker("Account", $draft.accountID)
                    }
                }
                Section("Schedule") {
                    Picker("Repeats", selection: $draft.spec.frequency) {
                        Text("Daily").tag(RecurrenceFrequency.daily)
                        Text("Weekly").tag(RecurrenceFrequency.weekly)
                        Text("Monthly").tag(RecurrenceFrequency.monthly)
                        Text("Yearly").tag(RecurrenceFrequency.yearly)
                    }
                    Stepper("Every \(draft.spec.interval) \(unitName)", value: $draft.spec.interval, in: 1...12)
                    if draft.spec.frequency == .weekly {
                        WeekdayPicker(selection: $draft.spec.weekdays)
                    }
                    if draft.spec.frequency == .monthly {
                        Picker("On day", selection: Binding($draft.spec.dayOfMonth, default: Calendar.current.component(.day, from: draft.spec.startDate))) {
                            ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                        }
                    }
                    DatePicker("Starts", selection: $draft.spec.startDate)
                    Toggle("Ends", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("End date", selection: Binding($draft.spec.endDate, default: .now.addingTimeInterval(365 * 86_400)), displayedComponents: .date)
                    }
                }
                Section {
                    Picker("When due", selection: $draft.mode) {
                        Text("Log automatically").tag(RecurringMode.autoPost)
                        Text("Remind me to confirm").tag(RecurringMode.remind)
                    }
                    if rule != nil {
                        Toggle("Active", isOn: $draft.isActive)
                    }
                } footer: {
                    Text(draft.mode == .autoPost
                         ? "Knock adds it on the due date — next time you open the app, or in the background."
                         : "You get a notification on the due date; mark it paid from Budgets → Upcoming.")
                }
            }
            .navigationTitle(rule == nil ? "New Recurring" : "Edit Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save).disabled((amount ?? 0) <= 0)
                }
            }
            .onAppear {
                if draft.accountID == nil { draft.accountID = (accounts.first(where: \.isDefault) ?? accounts.first)?.id }
            }
            .onChange(of: draft.kind) { _, kind in
                if let id = draft.categoryID, categories.first(where: { $0.id == id })?.kind != kind.categoryKind { draft.categoryID = nil }
            }
            .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var unitName: String {
        let plural = draft.spec.interval > 1
        switch draft.spec.frequency {
        case .daily: return plural ? String(localized: "days") : String(localized: "day")
        case .weekly: return plural ? String(localized: "weeks") : String(localized: "week")
        case .monthly: return plural ? String(localized: "months") : String(localized: "month")
        case .yearly: return plural ? String(localized: "years") : String(localized: "year")
        }
    }

    private func accountPicker(_ title: LocalizedStringKey, _ selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(accounts) { Text($0.displayName).tag(Optional($0.id)) }
        }
    }

    private func save() {
        var final = draft
        final.amount = amount ?? 0
        final.currencyCode = settings.currencyCode
        if !hasEnd { final.spec.endDate = nil }
        if final.spec.frequency != .monthly { final.spec.dayOfMonth = nil }
        if final.spec.frequency != .weekly { final.spec.weekdays = [] }
        do {
            let service = RecurringService(context: context, calculator: settings.calculator)
            try service.save(final, editing: rule)
            try service.postDue()
            if final.mode == .remind {
                Task { _ = await NotificationScheduler.shared.requestAuthorization() }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: [Int]

    var body: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        HStack {
            ForEach(1...7, id: \.self) { day in
                let isOn = selection.contains(day)
                Button(symbols[day - 1]) {
                    if isOn { selection.removeAll { $0 == day } } else { selection.append(day) }
                }
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .circle)
                .foregroundStyle(isOn ? .white : .primary)
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

extension Binding {
    /// A non-optional binding over an optional value with a fallback.
    init(_ source: Binding<Value?>, default fallback: Value) {
        self.init(get: { source.wrappedValue ?? fallback }, set: { source.wrappedValue = $0 })
    }
}

// MARK: - Goals

struct GoalRow: View {
    let goal: SavingsGoal
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color(.tertiarySystemFill), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: GoalService.progress(goal))
                    .stroke(Color(hex: goal.colorHex), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(goal.emoji).font(.callout)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name)
                Text("\(MoneyFormat.string(minor: GoalService.savedMinor(goal), currencyCode: currencyCode, showsFraction: false)) of \(MoneyFormat.string(minor: goal.targetMinor, currencyCode: currencyCode, showsFraction: false))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(GoalService.progress(goal).formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct GoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var name = ""
    @State private var emoji = "🎯"
    @State private var colorHex = "#0A84FF"
    @State private var target: Decimal?
    @State private var hasDate = false
    @State private var date = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal (e.g. Goa trip, Emergency fund)", text: $name)
                TextField("Target amount", value: $target, format: .number)
                    .keyboardType(.decimalPad)
                Toggle("Target date", isOn: $hasDate)
                if hasDate {
                    DatePicker("By", selection: $date, in: Date.now..., displayedComponents: .date)
                }
                Section("Icon") {
                    EmojiField(emoji: $emoji, suggestions: ["🎯", "🏖️", "🚗", "🏠", "💍", "🎓", "📱", "💻", "🛡️", "✈️", "👶", "🎸"])
                    ColorPaletteGrid(selection: $colorHex)
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        do {
                            try GoalService(context: context).add(name: name, emoji: emoji, colorHex: colorHex, target: target ?? 0,
                                                                  targetDate: hasDate ? date : nil, currencyCode: settings.currencyCode)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (target ?? 0) <= 0)
                }
            }
            .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

struct GoalDetailView: View {
    let goal: SavingsGoal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var amount: Decimal?
    @State private var note = ""
    @State private var confirmsDelete = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Color(.tertiarySystemFill), lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: GoalService.progress(goal))
                            .stroke(Color(hex: goal.colorHex), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.snappy, value: GoalService.progress(goal))
                        VStack {
                            Text(goal.emoji).font(.largeTitle)
                            Text(GoalService.progress(goal).formatted(.percent.precision(.fractionLength(0))))
                                .font(.title2.bold().monospacedDigit())
                        }
                    }
                    .frame(width: 160, height: 160)
                    Text("\(money(GoalService.savedMinor(goal))) of \(money(goal.targetMinor))")
                        .font(.headline)
                        .monospacedDigit()
                    if let monthly = GoalService.monthlyNeededMinor(goal) {
                        Text("Save \(money(monthly)) a month to make it by \(goal.targetDate?.formatted(date: .abbreviated, time: .omitted) ?? "")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
                .accessibilityElement(children: .combine)
            }
            Section("Add money") {
                TextField("Amount (negative to withdraw)", value: $amount, format: .number)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Note", text: $note)
                Button("Add contribution", systemImage: "plus.circle.fill") {
                    try? GoalService(context: context).contribute(amount ?? 0, to: goal, currencyCode: settings.currencyCode, note: note)
                    amount = nil
                    note = ""
                }
                .disabled((amount ?? 0) == 0)
            }
            Section("History") {
                ForEach((goal.contributions ?? []).sorted { $0.date > $1.date }) { contribution in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(contribution.date.formatted(date: .abbreviated, time: .omitted))
                            if !contribution.note.isEmpty {
                                Text(contribution.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(MoneyFormat.string(minor: contribution.amountMinor, currencyCode: settings.currencyCode, sign: .explicit))
                            .monospacedDigit()
                    }
                }
                .onDelete { offsets in
                    let sorted = (goal.contributions ?? []).sorted { $0.date > $1.date }
                    for index in offsets { context.delete(sorted[index]) }
                    try? context.save()
                }
            }
            Section {
                Button("Delete goal", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            }
        }
        .navigationTitle(goal.name)
        .confirmationDialog("Delete this goal and its history?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                try? GoalService(context: context).delete(goal)
                dismiss()
            }
        }
    }

    private func money(_ minor: Int64) -> String {
        MoneyFormat.string(minor: minor, currencyCode: settings.currencyCode, showsFraction: false)
    }
}
