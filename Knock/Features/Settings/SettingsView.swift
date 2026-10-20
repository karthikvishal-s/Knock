import AppIntents
import KnockKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder) private var accounts: [Account]

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Currency", value: "\(settings.currencyCode) (\(MoneyFormat.symbol(for: settings.currencyCode)))")
                    Picker("Default account", selection: defaultAccount) {
                        ForEach(accounts) { account in
                            Text(account.displayName).tag(Optional(account.id))
                        }
                    }
                } header: {
                    Text("General")
                }

                Section("Manage") {
                    NavigationLink { AccountsView() } label: { Label("Accounts", systemImage: "wallet.bifold") }
                    NavigationLink { CategoriesView() } label: { Label("Categories", systemImage: "square.grid.2x2") }
                    NavigationLink { TagsView() } label: { Label("Tags", systemImage: "number") }
                }

                Section {
                    Picker("Cycle starts on", selection: $settings.cycleStartDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("Day \(day)").tag(day)
                        }
                    }
                    Picker("First day of week", selection: $settings.firstWeekday) {
                        Text("System").tag(0)
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                    }
                } header: {
                    Text("Periods")
                } footer: {
                    Text("“This month” runs from this day. In shorter months, a cycle that starts on the 29th–31st begins on the month's last day.")
                }

                Section {
                    Picker("Back Tap & Siri open", selection: $settings.captureMode) {
                        Text("Quick prompts").tag(AppSettings.CaptureMode.inPlace)
                        Text("App keypad").tag(AppSettings.CaptureMode.sheet)
                    }
                    Toggle("Ask for a note", isOn: $settings.asksNote)
                    Toggle("Ask which account", isOn: $settings.asksAccount)
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                } header: {
                    Text("Capture")
                } footer: {
                    Text(settings.captureMode == .inPlace
                         ? "Quick prompts log without opening Knock: amount, then category. The account is only asked when you have more than one."
                         : "Back Tap and Siri open Knock straight into the keypad.")
                }

                Section {
                    Button("Set up Back Tap", systemImage: "hand.tap") { router.showsBackTapGuide = true }
                    ShortcutsLink()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Back Tap & Siri")
                } footer: {
                    Text("Say “Log expense in Knock” or “How much did I spend in Knock” to Siri.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionString)
                } footer: {
                    Text("All data stays on this iPhone. No account, no analytics, no ads.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    /// Exactly one account carries `isDefault`.
    private var defaultAccount: Binding<UUID?> {
        Binding {
            accounts.first(where: \.isDefault)?.id ?? accounts.first?.id
        } set: { id in
            for account in accounts {
                account.isDefault = account.id == id
            }
            try? context.save()
        }
    }
}

private extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .previewEnvironment()
}
