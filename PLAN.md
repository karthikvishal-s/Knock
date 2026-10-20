# PLAN — Back-Tap Expense & Income Tracker (codename **Knock**)

> Status: **APPROVED 2026-10-19 — name: Knock. M0 in progress.**
> Date: 2026-10-19 · Author: Karthik Vishal (with Claude Code)

---

## 1. Summary

A private, on-device personal finance app for one iPhone. Its main feature is **logging a transaction in under 3 seconds without opening the app**: double-tap the back of the phone, type an amount, pick a category, done. One set of App Intents powers every capture route (Back Tap via Shortcuts, Siri, Spotlight, widgets, Control Center, the in-app "+").

Compared with the app that inspired it, it adds **income**, **accounts and transfers**, **budgets with a configurable cycle**, **recurring transactions**, **savings goals** and **full Swift Charts analytics**. It reproduces the functionality only: no name, icon, screenshots or artwork are copied.

### Name suggestions (pick one before M1; the codename is used until then)

| Name | Why |
|---|---|
| **Knock** | You knock twice on the back of the phone. Short, verb-like, and easy for Siri to recognise ("Knock an expense…"). |
| **Tally** | The classic word for counting money. Neutral and calm, and fits the minimal, glassy look. |
| **Paisa Pulse** | INR-flavoured, and suggests checking the pulse of your cash flow. Distinct in Siri phrases. |

The name also becomes `\(.applicationName)` in every Siri phrase, so it should be easy to say and hard to mishear. **Knock** and **Tally** score best on that.

---

## 2. Environment, assumptions & answers

### Environment (inspected 2026-10-19)
| Item | Value |
|---|---|
| Xcode | **27.1** (27A9275) |
| Swift | **6.4** |
| iOS SDK | **27.1** (device + simulator SDKs) |
| Simulator runtimes | **None installed.** M0 downloads one (`xcodebuild -downloadPlatform iOS`). |
| Project folder | `~/tappy_v1`, empty. A new git repo is initialised here, separate from the home-directory repo. |

### Your answers
| # | Question | Answer | Consequence for the plan |
|---|---|---|---|
| 1 | Developer account | **Free Apple ID (Personal Team)** | No CloudKit. Provisioning profiles expire every **7 days**, so you re-run from Xcode weekly. App Groups must be proven in an M0 spike, with a fallback ready (§9, §12). |
| 2 | Device | **iPhone 13/14/15 (no Action Button), iOS 27.x** | The Action Button gets App Shortcuts automatically at zero cost, but isn't tested on your device. Back Tap, Siri, widgets and Control Center are all available. |
| 3 | Currency | **INR, single currency in v1** | Every row stores `currencyCode`, and the FX fields exist in the schema but stay hidden in the UI. Multi-currency is a post-v1 milestone. |
| 4 | Cycle start | **1st of the month** (configurable 1–31 in Settings) | `PeriodCalculator` still supports any start day from day one, and it's tested. |
| 5 | Capture mode | **In-place prompts** (default); app-sheet mode available in Settings | §3.2 |
| 6 | Note/account prompts | **Only when opted in** | Default flow is **amount → category → save**. Settings has toggles for "Ask for note" and "Ask for account (when >1)". |
| 7 | iCloud | **Local-only + JSON/CSV backup** | Models are still CloudKit-compatible, so sync can be switched on later with a paid account. |
| 8 | Visual style | **Glassy / native Liquid Glass** | System materials for navigation and controls; content stays on solid backgrounds for legibility. |
| 9 | Distribution | **Personal only** | No App Store review or privacy-label section. |
| — | Deployment target | **iOS 27.0** | See below. |
| — | Git | Own repo in `~/tappy_v1` | `.gitignore` for Xcode added in M0. |

### Deployment target: iOS 27.0
- Your only device runs iOS 27, and the app is personal-only, so supporting older versions has no benefit and would add `if #available` branches.
- It unlocks, with no gating: interactive **App Intent snippets** (`SnippetIntent`, `Button(intent:)`, iOS 26), `supportedModes` / `continueInForeground` (runtime choice between in-place and app-sheet capture, iOS 26), `requestChoice` (iOS 26), **Liquid Glass** (iOS 26), `ControlWidget` (iOS 18), SwiftData `#Index` (iOS 18), and the **`AppIntentsTesting`** framework (iOS 27) for out-of-process intent tests.

### Corrections and clarifications to the brief
1. **Haptics from background intents.** An intent running in-place (app not foreground) can't reliably play a haptic, because there's no UI scene. The confirmation is the system snippet UI. A light haptic plays in app-sheet mode and in-app only.
2. **Back Tap deep-linking.** Apps can't deep-link into Settings → Accessibility → Touch → Back Tap. Private `prefs:` URLs are unsupported and unstable. `UIApplication.openSettingsURLString` only opens the app's own Settings page. The guide uses illustrated steps plus a plain "Open Settings" button.
3. **App Shortcuts vs the Back Tap picker.** As the brief says, Back Tap lists only shortcuts in the **Shortcuts library**. The guide has you create a one-action shortcut (reliable on every iOS version). It also offers `ShortcutsLink` to jump to the app's page in Shortcuts. I couldn't find iOS 27 documentation saying this changed; **this gets re-verified on device in M2** (QA checklist §11.3).
4. **Widgets can't prompt for parameters.** A widget button can't show the amount/category prompts. Widget and Control Center "Log" buttons open the app straight into the quick-entry sheet. Whether a Control Center button can instead run the in-place prompt flow gets checked in M6; if it can, it becomes an option.
5. **Siri entitlement.** App Intents + `AppShortcutsProvider` do **not** need the SiriKit entitlement, which is only for legacy `INIntent`s. Siri phrases work on a free account.
6. **Decimal in storage.** The domain layer uses `Decimal` everywhere. SwiftData persists **`Int64` minor units** (paise) because `Decimal` storage, predicates and sorting in SwiftData are unreliable and slow to aggregate. See §4.

---

## 3. Back Tap / App Intents design

### 3.1 Where intents live: the app target
- **Decision:** capture intents (`LogExpenseIntent`, `LogIncomeIntent`, `QuickLogIntent`, `RepeatLastTransactionIntent`, `MonthSummaryIntent`) and the `AppShortcutsProvider` live in the **app target**. Intents that widgets/controls also use (`OpenQuickEntryIntent`) live in the shared `KnockKit` package, registered with `AppIntentsPackage` in both targets.
- **Why not an App Intents extension?** An extension avoids launching the app process, which saves a little latency. But it must share the store through an **App Group**, the one capability that's uncertain on a free account. With intents in the app target, the hero feature works even if App Groups fail.
- **Cost:** the app launches in the background without UI. Startup must stay light: lazily build the `ModelContainer` and don't load analytics on launch. **Budget: < 300 ms from intent start to the amount prompt** (measured in M2 with `os_signpost`).
- **Escape hatch:** if M2 measurements show unacceptable latency **and** App Groups work, move the capture intents into an App Intents extension. The code is already isolated in `Intents/` and only calls `TransactionService`.

### 3.2 Capture modes (Settings → Capture mode)
| Mode | Mechanism |
|---|---|
| **In-place (default)** | `static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]`. `perform()` runs in the background and gets values with parameter prompts / `requestDisambiguation` / `requestChoice`, then returns dialog plus an **interactive snippet**. |
| **App sheet** | The same intents. At the top of `perform()`, if `settings.captureMode == .sheet`, it calls `try await continueInForeground(alwaysConfirm: false)` and posts a `DeepLink.quickEntry(kind:)` to the app's router, which presents the full-screen `QuickEntrySheet`. |

> The `supportedModes` / `continueInForeground` signatures are verified against the 27.1 SDK headers on the first day of M2. If they behave differently, the fallback is two intent variants with `openAppWhenRun = true/false`, chosen in Settings and wired into the App Shortcuts.

### 3.3 Intents

**`LogExpenseIntent`**: "Log Expense"
| Parameter | Type | Prompt (in order) | Notes |
|---|---|---|---|
| `amount` | `Double` → converted to `Decimal` | 1. "How much did you spend?" | Shortcuts shows a **decimal keypad** for `Double`. It converts with `Decimal(string: amount.formatted(.number.precision(.fractionLength(0...2)).locale(.posix)))` to avoid binary-float artefacts, then rounds to the currency's minor units. `IntentCurrencyAmount` gets spiked in M2; it's used only if its prompt doesn't add a currency step. |
| `category` | `CategoryEntity` | 2. "Category?" | Filled with `requestDisambiguation(among: rankedExpenseCategories, dialog:)`, **ranked** (§3.5) so the most likely picks are on top. |
| `note` | `String?` | 3. "Add a note?" (skippable) | Asked only if **Settings → Ask for note** is on. |
| `account` | `AccountEntity?` | 4. "Which account?" | Asked only if **Ask for account** is on **and** there's more than one active account. Otherwise the default account is used. |
| `isCredit` | `Bool` = false | not prompted | Exposed for Shortcuts power users ("Log credit"). In-app it's the keypad toggle. |
| `date` | `Date` = now | not prompted | Lets Shortcuts automations backdate. |

**`LogIncomeIntent`**: "Log Income". Same as above with income categories and "How much did you receive?". No `isCredit`.

**`QuickLogIntent`**: "Quick Log". Amount, then `requestChoice` between **Expense / Income / Credit-Refund**, then category of that kind, then optional note/account.

**`RepeatLastTransactionIntent`**: "Repeat Last". Finds the newest non-transfer transaction and calls `requestConfirmation(actionName: .add, snippetIntent: RepeatPreviewSnippet)` ("₹120 · Coffee · Wallet — add again?"). On confirm it saves a copy dated now.

**`MonthSummaryIntent`**: "How much have I spent this month?" Returns dialog only: "₹4,320 spent of ₹15,000 · ₹610/day safe to spend". `authenticationPolicy = .requiresAuthentication`.

**`OpenQuickEntryIntent`** (`KnockKit`, used by widgets/controls): `kind: TransactionKindAppEnum`, `openAppWhenRun = true`. Routes to `QuickEntrySheet`.

**Snippet helpers** (`SnippetIntent`, iOS 26+):
- `LoggedConfirmationSnippet(transactionID:)` renders the confirmation card with buttons **Undo** (`UndoTransactionIntent`) and **Add note** (`AddNoteIntent`, which prompts for text).
- `UndoTransactionIntent(id:)` deletes that transaction (only if created < 10 minutes ago) and updates the snippet to "Removed".

### 3.4 Save pipeline (shared by every route)
`TransactionService.add(draft) async throws -> SavedTransaction`, a `@ModelActor`:
1. Validate (amount > 0, ≤ ₹10,00,00,000, category kind matches type).
2. Insert, set `source` (`.backTap/.siri/.shortcut/.widget/.control/.app/.recurring/.import`; intents can't tell Back Tap from Shortcuts, so they record `.shortcut`), and bump the category's `usageCount` and `lastUsedAt`.
3. `save()`, then `DataVersion.bump()` (an app-group `UserDefaults` counter that invalidates analytics caches).
4. `WidgetSnapshotWriter.write()`, then `WidgetCenter.shared.reloadAllTimelines()` + `ControlCenter.shared.reloadAllControls()`.
5. `BudgetAlertService.evaluate(after:)` posts a local notification if a threshold was crossed (deduplicated per cycle).

**Dialog/snippet text**
- Expense: **"₹250 · 🍔 Food"**, subtitle **"₹4,320 spent this month · ₹610/day left"**.
- Credit: **"+₹250 refund · 🛍 Shopping"** (green), subtitle "₹4,070 spent this month".
- Income: **"+₹50,000 · 💼 Salary"**, subtitle "₹62,000 income this month".
- If App Lock is on **and** "Hide totals in confirmations" is on, only the first line is shown.

### 3.5 Entities & queries
- **`CategoryEntity: AppEntity`**: `id: UUID`, `name`, `emoji`, `kind`. Display: `"\(emoji) \(name)"`.
  - `CategoryQuery: EntityStringQuery`: `entities(for:)`, `entities(matching:)` (localized contains), and `suggestedEntities()` ranked by **score = 3·(uses in last 30 days) + 2·(1 if used in last 48 h) + 1/(1 + days since last use)**, with archived categories excluded. Expense and income are filtered by an `IntentParameterDependency` on the intent kind, or by separate `ExpenseCategoryQuery` / `IncomeCategoryQuery` (simpler, so that's the default).
- **`AccountEntity: AppEntity`**: `id`, `name`, `emoji`, `kind`. `AccountQuery` returns active accounts with the default first.
- **`TransactionKindAppEnum`**: expense / income / refund / transfer.
- `KnockShortcuts.updateAppShortcutParameters()` is called after category changes so parameterised Siri phrases stay in sync.

### 3.6 App Shortcuts & Siri phrases (`AppShortcutsProvider`)
| Shortcut | Phrases (each must contain `\(.applicationName)`) | Tile |
|---|---|---|
| Log Expense | "Log expense in ${app}", "Add expense to ${app}", "${app} expense", "Log \(\.$category) expense in ${app}" | `minus.circle` |
| Log Income | "Add income in ${app}", "Log income in ${app}", "${app} income" | `plus.circle` |
| Quick Log | "Quick log in ${app}" | `bolt.circle` |
| Repeat Last | "Repeat last in ${app}", "Log that again in ${app}" | `arrow.clockwise.circle` |
| Month Summary | "How much did I spend in ${app}", "${app} summary" | `chart.pie` |

These appear in Spotlight and Siri, and on the Action Button on iPhone 15 Pro+ with no extra code. `ShortcutsLink()` sits on the Settings and onboarding screens.

### 3.7 Back Tap setup guide (onboarding + Settings → Set up Back Tap)
Paged sheet, one illustration per step (SF Symbols composition + device mock), progress dots:
1. **"Log in two taps on the back of your phone"**: explains Double Tap = Expense, Triple Tap = Income. Button: *Set it up*.
2. **"Create the shortcut"** (Shortcuts app):
   1. Tap **Open Shortcuts** (opens the Shortcuts app).
   2. Tap **＋** → **Add Action** → search **"Knock"** → choose **Log Expense**.
   3. Tap the name at the top → rename to **"Log Expense"** → **Done**.
   4. Repeat for **Log Income**.
   - Alternative, shown if verified in M2: `ShortcutsLink` → app page → long-press **Log Expense** → **Add to Shortcuts**.
3. **"Assign it to Back Tap"**: Settings → **Accessibility** → **Touch** → scroll to **Back Tap** → **Double Tap** → scroll to **Shortcuts** → **Log Expense**. Then go back → **Triple Tap** → **Log Income**. Button: *Open Settings* (opens the Settings app; the user navigates from there).
4. **"Try it now"**: "Double-tap the back of your iPhone." While this page is visible, the app watches `DataVersion`. When a transaction with `source == .shortcut` arrives within 2 minutes, the page shows **"✓ Back Tap works"** and offers to delete the test entry.
5. Done. Tip: Back Tap can misfire in a pocket or with thick cases; adjust in Settings if so.

---

## 4. Data model (SwiftData, `SchemaV1`)

**CloudKit-ready rules applied everywhere:** no `@Attribute(.unique)` / `#Unique`, every stored property has a default or is optional, every relationship is optional with an explicit inverse, enums are stored as raw `String`, and there are no `Decimal` or `Codable` blobs in queryable fields. `@Attribute(.externalStorage)` is used for receipt images.

**Money:** stored as `amountMinor: Int64` in the transaction's currency (INR: paise, so ₹250.50 is `25050`). The `Money` value type (`Decimal` amount + `CurrencyCode`) is the only API the UI and services use. Minor-unit exponent comes from `Locale.Currency` / ISO 4217 data (INR 2, JPY 0, BHD 3).

### `Transaction`
| Field | Type | Default | Notes |
|---|---|---|---|
| `id` | `UUID` | `UUID()` | Stable ID for entities, deep links, CSV/JSON |
| `kindRaw` | `String` | `"expense"` | expense / income / refund / transfer |
| `amountMinor` | `Int64` | 0 | Always positive. The sign comes from the kind. |
| `currencyCode` | `String` | `"INR"` | |
| `originalAmountMinor` | `Int64?` | nil | FX (post-v1 UI) |
| `originalCurrencyCode` | `String?` | nil | FX |
| `exchangeRateString` | `String?` | nil | `Decimal` stored as a string, used for display only |
| `date` | `Date` | `.now` | Editable. Backdating just changes this field. |
| `dayKey` | `Int32` | 0 | `yyyyMMdd` in the **device time zone at save time**. Recomputed on edit and in a time-zone-change sweep. Used for day grouping and the heatmap. |
| `note` | `String` | `""` | |
| `payee` | `String` | `""` | |
| `receiptImage` | `Data?` | nil | `.externalStorage`, HEIC, max 2048 px |
| `sourceRaw` | `String` | `"app"` | |
| `createdAt` / `updatedAt` | `Date` | `.now` | |
| `category` | `Category?` | nil | inverse `Category.transactions`, **nullify** |
| `account` | `Account?` | nil | Source account; inverse `Account.transactions`, **nullify** |
| `transferAccount` | `Account?` | nil | Destination for transfers; inverse `Account.incomingTransfers`, **nullify** |
| `tags` | `[Tag]?` | `[]` | Many-to-many; inverse `Tag.transactions` |
| `recurringRule` | `RecurringRule?` | nil | inverse `RecurringRule.generated`, **nullify** |

Indexes: `#Index<Transaction>([\.date], [\.dayKey], [\.kindRaw, \.date])`

### `Category`
`id UUID`, `name String = ""`, `emoji String = "🏷️"`, `colorHex String = "#8E8E93"`, `kindRaw String = "expense"`, `sortOrder Int = 0`, `isArchived Bool = false`, `usageCount Int = 0`, `lastUsedAt Date?`, `createdAt Date`.
Relationships: `parent: Category?` (inverse `children`, nullify), `children: [Category]?`, `transactions: [Transaction]?`, `budgets: [Budget]?` (cascade: a category's budgets go with it).
Deleting a category is replaced in the UI by **Archive** (keeps history) or **Merge into…** (reassigns transactions, budgets, rules and children, then deletes). Indexes: `[\.kindRaw, \.sortOrder]`.

Seed sets:
- **Expense:** Food 🍔, Groceries 🛒, Transport 🚕, Fuel ⛽, Shopping 🛍, Bills 🧾, Rent 🏠, Health 💊, Entertainment 🎬, Travel ✈️, Education 📚, Personal Care 💇, Gifts 🎁, EMI/Loans 🏦, Subscriptions 🔁, Other ⋯.
- **Income:** Salary 💼, Freelance 🧑‍💻, Business 🏪, Interest 🏦, Dividends 📈, Gifts 🎁, Refunds ↩️, Rental 🏘, Other ⋯.

### `Account`
`id`, `name = ""`, `kindRaw = "cash"` (cash / bank / creditCard / upiWallet / savings / other), `emoji = "💵"`, `colorHex`, `openingBalanceMinor Int64 = 0`, `openingDate Date`, `currencyCode = "INR"`, `creditLimitMinor Int64?`, `isArchived = false`, `isDefault = false`, `sortOrder = 0`, `createdAt`.
Relationships: `transactions`, `incomingTransfers`, `goals: [SavingsGoal]?` (all nullify).
An account with transactions can't be deleted, only archived. Seeded with **Cash** (default) and **Bank**.

### `Tag`
`id`, `name = ""`, `colorHex`, `transactions: [Tag↔Transaction]?`. Many-to-many, nullify.

### `Budget`
`id`, `category: Category?` (**nil = overall monthly budget**), `limitMinor Int64 = 0`, `rollover Bool = false`, `alertThresholds [Int] = [50, 80, 100]`, `isActive = true`, `createdAt`, `effectiveFrom Date` (rollover never reaches back before this).

### `RecurringRule`
`id`, `kindRaw`, `amountMinor`, `currencyCode`, `note`, `payee`, `category?`, `account?`, `transferAccount?`, `frequencyRaw` (daily/weekly/monthly/yearly), `interval Int = 1`, `weekdays [Int]?` (weekly), `dayOfMonth Int?` (monthly; 31 is clamped to the month's last day), `startDate`, `endDate?`, `nextDueDate`, `modeRaw` (autoPost / remind), `remindDaysBefore Int = 0`, `isActive = true`, `generated: [Transaction]?` (nullify).

### `SavingsGoal` / `GoalContribution`
`SavingsGoal`: `id`, `name`, `emoji`, `colorHex`, `targetMinor`, `targetDate?`, `isArchived`, `linkedAccount: Account?` (nullify), `contributions: [GoalContribution]?` (**cascade**).
`GoalContribution`: `id`, `amountMinor`, `date`, `note`, `goal?`.

### Non-SwiftData state
- **`AppSettings`** (`@Observable`, backed by app-group `UserDefaults`): base currency, cycle start day, first weekday, default account ID, capture mode, ask note, ask account, haptics, app lock, hide totals, reminder time, appearance, budget-alert dedup log `[cycleKey: [budgetID: lastThreshold]]`.
- **`WidgetSnapshot.json`** in the app group: a precomputed struct for widgets (§8).

### Migration
`enum SchemaV1: VersionedSchema` holds all the models above. `KnockMigrationPlan: SchemaMigrationPlan` has `schemas = [SchemaV1.self]` and `stages = []`. Each future change adds `SchemaV2` plus a `MigrationStage` (`.lightweight` where possible). The model classes are type aliases (`typealias Transaction = SchemaV1.Transaction`), so app code never names a schema version. A migration test opens a V1 fixture store with the newest schema.

---

## 5. Architecture & targets

### Principles
- **Feature folders.** Views + `@Observable` view models only where a screen has real logic (quick entry, history filters, analytics, import mapping). Simple screens use `@Query` directly.
- **Thin service layer** over SwiftData: `TransactionService`, `CategoryService`, `AccountService`, `BudgetService`, `RecurrenceService`, `AnalyticsService`, `ImportExportService`. Background work runs in `@ModelActor`s. UI reads with `@Query` on the main context.
- **Pure domain logic** (`PeriodCalculator`, `BudgetMath`, `ProjectionMath`, `RecurrenceEngine`, `CSVCodec`, `MoneyFormat`) has no SwiftData imports, so it's trivially unit-tested. It runs under `swift test` on the Mac with no simulator.
- **DI:** an `AppDependencies` struct (container, services, settings, clock, calendar) injected with `@Environment`. Tests and previews use `.preview` (in-memory store + sample data) and a fixed `Clock`.
- Swift 6 strict concurrency, `Sendable` value types for everything that crosses actors (`TransactionDraft`, `TxnPoint`, `PeriodSummary`).

### Targets
| Target | Contents |
|---|---|
| **Knock** (iOS app) | UI, App Intents, `AppShortcutsProvider`, deep-link router, notifications |
| **KnockWidgets** (Widget extension) | Home + Lock Screen widgets, `ControlWidget`s. Reads `WidgetSnapshot`; never writes the store. |
| **KnockKit** (local Swift package) | Models, persistence, domain math, formatting, `WidgetSnapshot`, `OpenQuickEntryIntent` + `AppIntentsPackage` |
| **KnockKitTests** (Swift Testing) | Domain + persistence tests (run with `swift test` or in Xcode) |
| **KnockTests** (Swift Testing, app-hosted) | Service tests against an in-memory container; `AppIntentsTesting` intent tests |
| **KnockUITests** (XCTest UI) | Add / edit / delete flow, quick-entry sheet |

### Folder tree
```
tappy_v1/
├── PLAN.md
├── .gitignore
├── Knock.xcodeproj
├── Knock/
│   ├── App/                KnockApp.swift · AppDependencies.swift · RootTabView.swift · DeepLinkRouter.swift · LockGate.swift
│   ├── Features/
│   │   ├── Home/           HomeView · HomeViewModel · SafeToSpendCard · BudgetRingCard · RecentList
│   │   ├── Capture/        QuickEntrySheet · Keypad · CategoryGrid · TransactionEditor · ReceiptPicker
│   │   ├── History/        HistoryView · HistoryViewModel · DaySection · FilterSheet · SearchSuggestions
│   │   ├── Analytics/      AnalyticsView · PeriodSwitcher · Dashboard/ · Categories/ · IncomeVsExpense/
│   │   │                   CashFlow/ · Trend/ · Insights/ · Year/ · Calendar/ · Accounts/ · BudgetPerf/ · Payees/
│   │   ├── Accounts/       AccountsList · AccountDetail · AccountEditor · TransferEditor
│   │   ├── Categories/     CategoriesList · CategoryEditor · EmojiPicker · ColorPalette · MergeSheet
│   │   ├── Budgets/        BudgetsView · BudgetEditor · BudgetDetail
│   │   ├── Recurring/      RecurringList · RuleEditor · UpcomingBills
│   │   ├── Goals/          GoalsList · GoalDetail · GoalEditor
│   │   ├── Settings/       SettingsView · CaptureSettings · AppearanceSettings · DataSettings · About
│   │   ├── Onboarding/     Welcome · BackTapGuide (5 pages) · SeedChoices
│   │   └── ImportExport/   ExportSheet · ImportFlow · ColumnMappingView · BackupRestore
│   ├── Intents/            LogExpenseIntent · LogIncomeIntent · QuickLogIntent · RepeatLastIntent
│   │                       MonthSummaryIntent · Snippets/ · Entities/ · KnockShortcuts.swift
│   ├── Services/           NotificationScheduler · BudgetAlertService · RecurrencePoster · HapticsService
│   └── Resources/          Assets.xcassets · Localizable.xcstrings · AppIcon
├── KnockWidgets/           KnockWidgetsBundle · QuickLogWidget · MonthWidget · SummaryWidget · LockWidgets · Controls
├── KnockKit/               (Swift package)
│   ├── Sources/KnockKit/
│   │   ├── Models/         SchemaV1.swift · MigrationPlan.swift · Enums.swift
│   │   ├── Persistence/    ContainerFactory · StoreLocation (app group w/ fallback) · DataVersion · SampleData
│   │   ├── Domain/         Money · CurrencyCatalog · MoneyFormat · PeriodCalculator · BudgetMath
│   │   │                   ProjectionMath · RecurrenceEngine · CSVCodec · BackupDTOs
│   │   ├── Services/       TransactionService · AnalyticsService · ImportExportService · …
│   │   └── Shared/         WidgetSnapshot · DeepLink · OpenQuickEntryIntent
│   └── Tests/KnockKitTests/
├── KnockTests/
└── KnockUITests/
```

---

## 6. Screens & navigation

`TabView` with the iOS 26+ `Tab` API and a Liquid Glass tab bar: **Home · History · Analytics · Budgets · Settings**. History uses `Tab(role: .search)`-style search with `.searchable`. A floating glass **"+"** button (`.glassEffect(.regular.interactive())`) sits on Home and History and opens `QuickEntrySheet`. Long-pressing "+" gives a menu: Expense / Income / Transfer / Repeat last.

| Screen / sheet | Purpose | Key components |
|---|---|---|
| **Home** | At-a-glance month | Cycle header ("Oct 1 – Oct 31"), Spent / Income / Net cards, Safe-to-spend card, budget ring, top 3 category budgets, upcoming bills (next 7 days), recent 10 transactions |
| **QuickEntrySheet** (full screen) | Fast in-app capture | Amount display, custom glass keypad, Expense/Income/Transfer segmented control, **Credit toggle**, ranked category grid, note field, account chip, date chip, save |
| **TransactionEditor** | Full edit | All fields: payee, tags, receipt photo (`PhotosPicker` / camera), date & time, duplicate, delete |
| **History** | Full ledger | Day sections with daily net totals, swipe edit/duplicate/delete, **undo toast**, search (note, payee, amount), filter sheet (type, category, account, tag, date range, amount range), active-filter chips |
| **Analytics** | Insights | Period switcher (Week / Month / Year / Custom) with swipe for previous/next; sections listed in §7 |
| ↳ CategoryDrilldown | Transactions in one category for the period | Bar trend + list |
| ↳ DayDetail | Transactions on a heatmap day | List + total |
| **Budgets** | Plan spending | Overall card, per-category rows with progress, over-budget in red, rollover badge; Goals and Recurring sections |
| ↳ BudgetEditor | Set limit, rollover, alert thresholds | |
| ↳ RecurringList / RuleEditor / UpcomingBills | Subscriptions, rent, salary, EMIs | Next-due dates, mode (auto / remind) |
| ↳ GoalsList / GoalDetail | Savings goals | Progress ring, contributions list, add contribution |
| **Settings** | Configuration | Currency, cycle day, first weekday, default account, **Capture** (mode, ask note, ask account, haptics), **Back Tap guide**, Accounts, Categories, Tags, Notifications (daily reminder time, budget alerts), App Lock (Face ID + hide totals), Appearance, Export / Import / Backup / Restore, Erase all, About |
| **Accounts** (from Settings + Analytics) | Wallets | Balances, net worth, credit-card outstanding/limit, transfer button |
| **Categories** | Customise | Expense/Income segments, drag reorder, emoji picker (any emoji with a system keyboard field + recents), 24-colour palette, archive, merge, sub-categories |
| **Onboarding** (first launch) | Setup | Welcome → currency confirm (INR) → starter accounts → Back Tap guide (skippable) |
| **LockGate** | Face ID overlay | Blur overlay when the scene is inactive (privacy in the app switcher) |

### Wireframe: QuickEntrySheet
```
┌─────────────────────────────────────┐
│ ✕                 Expense ▾   📅 Now │
│ [ Expense | Income | Transfer ]      │
│                                      │
│              ₹ 250.50                │  ← big, monospaced digits
│        ( ) Credit / refund           │  ← toggle, turns amount green
│                                      │
│ 🍔 Food  🛒 Groc  🚕 Taxi  ☕ Coffee │  ← ranked, 2 rows,
│ 🧾 Bills 🎬 Fun   🛍 Shop  ⋯ More    │     selected = glass highlight
│                                      │
│ 💵 Cash ▾        ✎ Add note…         │
│ ┌──────┬──────┬──────┐               │
│ │  1   │  2   │  3   │               │
│ │  4   │  5   │  6   │   glass keys  │
│ │  7   │  8   │  9   │               │
│ │  .   │  0   │  ⌫   │               │
│ └──────┴──────┴──────┘               │
│ [            Save ₹250.50          ] │
└─────────────────────────────────────┘
```

### Wireframe: Home
```
┌─────────────────────────────────────┐
│ October · Oct 1 – 31        ‹  ›     │
│ ┌───────────┬──────────┬──────────┐ │
│ │ Spent     │ Income   │ Net      │ │
│ │ ₹18,420   │ ₹62,000  │ +₹43,580 │ │
│ └───────────┴──────────┴──────────┘ │
│ ┌─ Safe to spend today ───────────┐ │
│ │ ₹610      12 days left  ◔ 64%   │ │
│ └─────────────────────────────────┘ │
│ Budgets   Food ▓▓▓▓▓░ 78%  Fun ▓▓░  │
│ Upcoming  Netflix ₹649 · Oct 22     │
│ Recent                               │
│  🍔 Food   Swiggy        −₹250  9:41 │
│  💼 Salary               +₹62,000    │
│                              ( + )   │ ← glass FAB
└─────────────────────────────────────┘
```

### Wireframe: Analytics
```
┌─────────────────────────────────────┐
│ [Week | Month | Year | Custom]       │
│ ‹  October 2026  ›   (swipe ↔)       │
│ Income ₹62k  Expense ₹18.4k  Net ₹43k│
│ Savings rate 70%                     │
│ ┌ Spending by category ───────────┐ │
│ │   ◯ donut   Food 32% ₹5,900  ›  │ │
│ │             Rent 27% ₹5,000  ›  │ │
│ └─────────────────────────────────┘ │
│ ┌ Insights ───────────────────────┐ │
│ │ Daily avg ₹974 · Projected ₹30.1k│ │
│ │ vs Sep same day: −₹1,200 (−6%)   │ │
│ │ Biggest: Rent ₹5,000 · 4 no-spend│ │
│ └─────────────────────────────────┘ │
│ Trend (daily bars + avg rule)        │
│ Income vs Expense (grouped bars)     │
│ Cash flow (cumulative net line)      │
│ Calendar heatmap                     │
│ Budget vs actual · Accounts · Payees │
└─────────────────────────────────────┘
```

---

## 7. Analytics computation

### 7.1 Definitions (all values as `Decimal`, period = `[start, end)`)
- **Expenses (net)** `E = Σ expense − Σ refund`. Refunds reduce spending and show in green. A refund-heavy category can go negative; it's shown as "credit" and excluded from the donut.
- **Income** `I = Σ income`. **Transfers are excluded** from I and E.
- **Net cash flow** `N = I − E`.
- **Savings rate** `= N / I` when `I > 0`, else "—". Shown as a %; can be negative.
- **Daily average** `= E / daysElapsed`, where `daysElapsed = days from period start through today` (the whole period if it's in the past).
- **Projected month-end** `= E_variable + (E_variable / daysElapsed) × daysRemaining + Σ scheduled recurring expenses still due this cycle`, where `E_variable` excludes transactions generated by recurring rules. This stops rent on the 1st from inflating the daily rate. Only shown when `daysElapsed ≥ 3`.
- **Safe to spend today** (overall budget `B`, cycle `[s, e)`):
  `available = B + rolloverIn − E(s ..< startOfToday) − Σ upcoming recurring expenses until e`
  `perDay = max(0, available) / daysRemainingIncludingToday`
  `leftToday = perDay − E(today)`. The card shows `leftToday` (red if < 0) and `perDay`.
- **Rollover** (per budget with `rollover = true`): `rolloverIn(c) = max(0, B + rolloverIn(c−1) − E(c−1))`, iterated from `effectiveFrom`, capped at 12 cycles.
- **Comparison with last period**: same elapsed-day window. Oct 1–19 is compared with Sep 1–19, not the whole of September. Shows Δ amount and Δ % (or "new" if the previous value was 0).
- **No-spend days** = days in `[s, min(today, e))` with no expense rows (refunds don't count as spending).
- **Biggest expense**: max single expense. **Most frequent category**: highest count.
- **Account balance** = opening + Σ income + Σ refund − Σ expense − Σ transfer-out + Σ transfer-in, for rows on that account dated ≥ `openingDate`. **Credit card outstanding** = `−balance` when the balance is < 0.
- **Net worth** = Σ active-account balances (base currency; FX conversion post-v1).
- **Balance over time**: daily cumulative series per account, sampled weekly when the range is > 120 days.

### 7.2 `PeriodCalculator` (pure, heavily tested)
- Inputs: `Calendar` (with `timeZone` and `firstWeekday`), `cycleStartDay` (1–31), and a reference date.
- `cycle(containing:)`: start is `cycleStartDay` clamped to the month's length (start day 31 → Feb 28/29, Apr 30). The end is the next cycle's start. Built from date components with `calendar.date(from:)` and never by adding 86,400 seconds, so DST is safe.
- `week(containing:)` respects `firstWeekday`. `year(containing:)` is the calendar year. `custom(start,end)` is normalised to day bounds.
- `previous/next(period)` for swipe navigation. `days(in:)` returns the list of days for the heatmap and trends.
- Every "This Month" label in the UI goes through `PeriodCalculator.currentCycle`.

### 7.3 Staying fast with 20,000+ rows
- **`AnalyticsService` is a `@ModelActor`.** It fetches `Transaction`s in the date range (indexed `date`) with `propertiesToFetch` limited to the needed columns and `relationshipKeyPathsForPrefetching: [\.category]`. It maps them to `Sendable struct TxnPoint { dayKey, kind, amountMinor, categoryID, accountID, isRecurring }` and aggregates in memory with `Int64` sums. 20k `Int64` additions take microseconds; the fetch dominates.
- **Memoisation:** results are cached by `(periodID, filterHash, DataVersion)`. `DataVersion` bumps on every save, so a cache hit is free and a write invalidates it.
- **Prefetch** the previous and next period after showing the current one, so swipes feel instant.
- **History:** paged fetch by month windows (2 cycles at a time, `fetchLimit` fallback) instead of a single `@Query` over 20k rows. Day totals are computed per page. Search uses `#Predicate` with `localizedStandardContains` on note/payee; a numeric query also matches `amountMinor ==`.
- **Performance budget, iPhone 13, 20k rows across 4 years:** Month dashboard < 120 ms, Year view < 350 ms, History first page < 80 ms, scroll at 60 fps. Measured with a seeded 20k store and `os_signpost` in M8.
- **Fallback if over budget:** add a `MonthlyRollup` model (`monthKey`, `categoryID`, `kind`, `sumMinor`, `count`), maintained incrementally in `TransactionService` and rebuildable from scratch. It's added only if the measurements require it, because incremental caches are a bug source.

### 7.4 Charts (Swift Charts)
`SectorMark` donut (inner radius 0.62, angular inset 1.5), `BarMark` grouped by `.position(by:)` for income vs expense, `LineMark` + `AreaMark` for cumulative net, `BarMark` + `RuleMark` (average) for trend, a custom `Grid` heatmap (5-step sequential scale on the accent colour; tapping a cell opens DayDetail), and `.chartXSelection` for scrubbing. **Accessibility:** every chart gets `.accessibilityChartDescriptor` (audio graphs) and per-mark `.accessibilityLabel`/`.accessibilityValue`. Category colours come from a palette validated for dark mode (contrast ≥ 3:1 on both backgrounds).

---

## 8. Widgets & controls

Widgets read **`WidgetSnapshot.json`** from the app group, written by the app/intent after every save and at cycle rollover: `spentMinor`, `incomeMinor`, `budgetMinor`, `safePerDayMinor`, `leftTodayMinor`, `top3Categories`, `recent3`, `cycleStart/End`, `generatedAt`. That makes them fast, with no SwiftData in the extension. The timeline has an entry at each local midnight so safe-to-spend rolls over without the app running.

| Widget | Family | Shows | Interaction |
|---|---|---|---|
| **Quick Log** | systemSmall | Two big glass buttons: − Expense / + Income | `Button(intent: OpenQuickEntryIntent(kind:))` opens the quick-entry sheet |
| **This Month** | systemSmall | Spent, budget ring %, "₹610/day" | Tap opens Home |
| **Summary** | systemMedium | Spent / Income / Net, safe-to-spend, Expense & Income buttons | Buttons go to the sheet |
| **Overview** | systemLarge | Summary + top 3 budget bars + last 3 transactions | Rows deep-link to the editor |
| **Budget Ring** | accessoryCircular | Gauge of % of budget used | Tap opens the app |
| **Month Line** | accessoryRectangular | "₹18,420 spent · ₹610/day left" | |
| **Inline** | accessoryInline | "₹610 safe today" | |
| **Log Expense / Log Income** | `ControlWidgetButton` (Control Center, Lock Screen controls) | Icon + label | `OpenQuickEntryIntent`; in-place prompts checked in M6 |
| **Action Button** | (system) | App Shortcuts appear automatically | Nothing to build; can't be tested on your device |

Hide-totals privacy setting: when it's on, widgets show "•••" instead of amounts (`.privacySensitive()` + redaction on a locked device).

---

## 9. Capabilities, signing & installing (free Apple ID)

| Capability / key | Needed for | Free Personal Team? |
|---|---|---|
| **App Groups** (`group.com.karthikvishal.knock`) | Shared store + widget snapshot | **Uncertain → verified in M0 spike.** Same-team sharing is designed to work; several reports say Personal Teams can register app groups, but there's no authoritative confirmation. **Fallback:** store in the app container; widgets show only static Quick Log buttons with no amounts. Intents are unaffected (they're in the app target). |
| iCloud / CloudKit | Sync | **No.** Needs a paid membership. Deferred; models are already compatible. |
| Push notifications | — | Not needed. Local notifications need no entitlement. |
| Background Modes → Background fetch (Info.plist) | `BGAppRefreshTask` for recurring auto-post & widget snapshot | Yes (plist key only) |
| `NSFaceIDUsageDescription` | App Lock | Yes (usage string only) |
| `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` (add-only) | Receipt photos | Yes |
| Siri / App Shortcuts | Siri phrases | Yes (no entitlement for App Intents) |

### Installing on your iPhone
1. Xcode → Settings → Accounts → add your Apple ID (Personal Team).
2. In each target → Signing & Capabilities: Team = *Karthik Vishal (Personal Team)*. Bundle IDs are `com.karthikvishal.knock` and `.widgets`, and must be globally unique; change the prefix if registration fails.
3. iPhone: **Settings → Privacy & Security → Developer Mode → On** (restart).
4. Connect by cable (or the same Wi-Fi after the first pairing), select the device, then **Run**.
5. First launch: **Settings → General → VPN & Device Management → trust your developer profile**.

### Free-account limits
- **Provisioning profiles expire after 7 days.** The app then won't launch. **Re-run from Xcode** (no need to delete the app) to re-sign. **Your data is preserved** as long as you don't delete the app.
- Limits on how many App IDs you can create (about 10 per 7 days) and how many apps can be installed at once (about 3). Avoid churning bundle IDs; pick the final name **before M1**.
- **Mitigations:** a weekly calendar reminder, an **automatic JSON backup** to the app's Documents folder (visible in Files via `UIFileSharingEnabled`) every day the app opens (keeping the last 14), and a one-tap "Export backup" in Settings.

---

## 10. Milestones

**Order changed from the brief:** accounts and income (brief M4) move **before** analytics (brief M3). Every chart has to handle income, refunds and transfers; building analytics on expenses only and retrofitting would mean writing each chart twice. The data model covers everything from M1, so only UI work is reordered.

| # | Milestone | Ends with (on your phone) |
|---|---|---|
| **M0** | Setup & spikes: git, `.gitignore`, download the iOS 27.1 simulator, create the Xcode project + widget extension + `KnockKit` package, sign with the Personal Team, **App Group spike** (app writes a file, widget reads it on device), **intent spike** (a `Double` parameter prompt shows a decimal keypad; `continueInForeground` signature) | A blank app + "hello" widget on your phone; a go/no-go decision on App Groups |
| **M1** | Core: `SchemaV1`, `Money`, `PeriodCalculator`, seed data, `TransactionService`, in-app QuickEntrySheet, TransactionEditor, History (sections, swipe, undo, search, filters), basic Home, preview sample store | Log, edit, delete and search expenses and income in the app |
| **M2** | **Hero:** all capture intents, entities/queries with ranking, snippets (Undo / Add note), App Shortcuts + Siri phrases, capture-mode setting, Back Tap guide with live "Try it now" check, latency signposts | **Double-tap the back → ₹ → category → saved**, in under 3 seconds |
| **M3** | Accounts & income: accounts CRUD, transfers, balances, credit-card outstanding, net worth, income categories, category management (emoji, colour, reorder, archive, merge, sub-categories), tags, receipt photos | Multiple wallets with correct balances |
| **M4** | Analytics: `AnalyticsService` + cache, period switcher, dashboard, category donut + drill-down (expense & income), income vs expense, cash flow, trend, insights, year view, calendar heatmap, accounts chart, payees/tags | Full analytics tab |
| **M5** | Budgets & recurring: overall + category budgets, cycle day, rollover, safe-to-spend, alerts, recurring rules (auto-post / remind), upcoming bills, daily reminder, savings goals, budget-performance chart | Budget ring and alerts working; salary auto-posts |
| **M6** | Widgets & controls: snapshot writer, the 7 widgets, 2 controls, reload strategy, privacy redaction | Widgets on Home/Lock Screen; Control Center button |
| **M7** | Data & security: CSV export/import with column mapping, JSON backup/restore, auto backup, Face ID lock + app-switcher blur + hide totals, erase all | Import from your old app; Face ID lock |
| **M8** | Polish: 20k-row benchmark (+ `MonthlyRollup` if needed), Dynamic Type up to AX5, VoiceOver pass, empty states, String Catalog review, app icon (light/dark/tinted), final QA | Release-quality personal build |
| *M9 (later)* | Optional: multi-currency UI with manual rates; CloudKit sync after a paid upgrade | — |

---

## 11. Test plan

### 11.1 Automated (Swift Testing unless noted)
| Milestone | Tests |
|---|---|
| M1 | `PeriodCalculator`: cycle start 1/15/28/29/30/31 across Feb (leap and non-leap), 30-day months, year boundary, DST transitions (Asia/Kolkata has none, so tests also run America/New_York and Europe/London), `firstWeekday` 1 and 2; time-zone change and `dayKey`. `Money`: parse/format INR (lakh grouping `₹1,00,000.00`), rounding half-even to paise, `Double → Decimal` conversion edge cases (0.1+0.2, 19.99). `TransactionService`: add/edit/backdate moves period, delete + undo. |
| M2 | `CategoryQuery` ranking. Intent `perform` with injected services. **`AppIntentsTesting`** (iOS 27): run `LogExpenseIntent` out-of-process against the installed app and assert that a row exists. Snippet undo window. |
| M3 | Balance formula incl. transfers, refunds and opening date; merge categories reassigns everything; archive hides from pickers but keeps history. |
| M4 | Savings rate (I = 0, negative N), projection (excludes recurring, < 3 days hidden), same-day comparison, no-spend days, cache invalidation on `DataVersion`. |
| M5 | `RecurrenceEngine`: monthly on the 31st → Feb 28/29, weekly multi-weekday, yearly Feb 29, end date, catch-up posting after 10 days offline without duplicates (idempotent by rule + due date). Rollover chain. Safe-to-spend incl. upcoming bills. Alert dedup per cycle. |
| M6 | `WidgetSnapshot` encode/decode, snapshot values match `AnalyticsService` for the same store. |
| M7 | `CSVCodec` round-trip (quotes, commas, newlines in notes, ₹ symbol, UTF-8 BOM, `dd/MM/yyyy` vs ISO dates, negative amounts → refund). Import dedup. JSON backup → erase → restore gives identical counts and sums. |
| M8 | Performance test: seed 20k rows and assert the aggregation time budget (`XCTMetric` / signposts). Migration fixture test. |
| UI (XCTest) | Add expense via the sheet; edit amount; swipe delete + undo; search; quick entry with the credit toggle; Back Tap guide pages navigate. |
| Previews | Every screen has a `#Preview` using `AppDependencies.preview` (in-memory store with about 3 months of realistic INR data), plus an empty-state preview. |

### 11.2 Manual per milestone
Each milestone ends with a 10-minute on-device run of its "Ends with" scenario, in light and dark mode at the largest Dynamic Type size.

### 11.3 Back Tap QA checklist (real device)
- [ ] The shortcut created in the guide appears under Settings → Accessibility → Touch → Back Tap → Double Tap → Shortcuts.
- [ ] (Verify) Is adding the App Shortcut to the library via `ShortcutsLink` possible on iOS 27? Record the result and keep the better flow in the guide.
- [ ] Double tap with **app killed**: amount prompt in < 1 s; logging completes in < 3 s total with 2 categories ranked on top.
- [ ] Double tap with the **app in the foreground** on another tab: prompts appear and the app UI updates afterwards.
- [ ] Triple tap → Log Income → shows income categories only.
- [ ] Cancel at each prompt → nothing saved, no crash.
- [ ] Decimal entry `250.5` saves as ₹250.50; `0` and empty are rejected with a friendly dialog.
- [ ] Snippet **Undo** removes the row; **Add note** attaches the note.
- [ ] Ask-note and ask-account toggles change the prompt sequence; with one account, no account prompt.
- [ ] App-sheet mode: Back Tap opens straight into the QuickEntrySheet (keyboard-free keypad visible).
- [ ] With **App Lock on**: logging still works; the snippet hides totals if that setting is on.
- [ ] Phone locked / on the Lock Screen: document what Back Tap does (it's expected to require unlock).
- [ ] Repeat Last via Siri: confirmation snippet → saved.
- [ ] Widget and budget ring update within a few seconds of a Back Tap log.
- [ ] Budget alert notification fires once when crossing 80%, not again on the next log.
- [ ] Airplane mode: everything works (no network use at all).
- [ ] After the 7-day re-sign (re-run from Xcode): data intact, Back Tap shortcut still works.

---

## 12. Risks & open questions

| Risk | Impact | Mitigation |
|---|---|---|
| **App Groups unavailable on a free Personal Team** | Widgets can't read data | M0 spike before any feature work. Fallback: widgets without amounts (quick-log buttons only); intents in the app target are unaffected. A paid upgrade later turns full widgets on without code changes (`StoreLocation` picks the group container when it's available, and migrates the file). |
| **7-day profile expiry** | App stops launching weekly | Re-run from Xcode; data persists. Daily auto JSON backup to Files. |
| **Intent execution limits / background launch latency** | Back Tap feels slow, or the system kills the intent | Lazy container, no work at launch, signposts with a 300 ms budget. Time spent waiting for user input doesn't count as execution, but `perform` after the last prompt must finish within ~1–2 s (the save is < 50 ms). Escape hatch: App Intents extension (§3.1). |
| **Back Tap picker behaviour changes in iOS 27** | The guide is wrong | Verify on device in M2 (checklist §11.3); guide text lives in one file. |
| **`continueInForeground` / `supportedModes` semantics** | Runtime capture-mode switching | Verified in the M0 spike; fallback is two intent variants. |
| **Parameter prompt keypad for decimals** | Typing ₹250.50 is awkward | M0 spike compares `Double`, `IntentCurrencyAmount` and `String` + validation. |
| **SwiftData performance at 20k+ rows** | Laggy History/Analytics | Background actor aggregation, caching keyed by `DataVersion`, paged History, `MonthlyRollup` fallback, M8 benchmark. |
| **SwiftData + concurrency edge cases** (Swift 6) | Crashes passing models across actors | Only `PersistentIdentifier` / `UUID` / `Sendable` DTOs cross actors; `@ModelActor` for writes off-main. |
| **Widget refresh budget** | Stale widgets | The app reloads timelines on each save (free while foreground; background reloads are budgeted at about tens per day). Midnight entries handle the day rollover. Snapshot `generatedAt` shown subtly ("updated 9:41"). |
| **Recurring auto-post when the app isn't opened** | Salary not posted on time | Catch-up on every launch/intent run + `BGAppRefreshTask` (best effort) + a notification on the due date. Idempotent posting. |
| **Local notification cap (64 pending)** | Missed reminders | Rolling 30-day schedule, re-planned on each launch. |
| **CloudKit later** | Schema incompatibilities | Rules applied from V1; a unit test reflects over the schema to assert "no unique attributes, all relationships optional". |
| **Losing data by deleting the app** | Total loss (local-only) | Auto backups + an onboarding note; "Erase all" requires typing ERASE. |

### Resolved (2026-10-19)
1. App name: **Knock**. Bundle IDs `com.karthikvishal.knock` and `com.karthikvishal.knock.widgets`; app group `group.com.karthikvishal.knock`.
2. Back Tap logging **works while App Lock is on**, with totals hidden in the snippet (the "Hide totals" default is on when App Lock is on).
3. CSV import: a **general** importer with column mapping (no specific source app); see M7.
4. Daily reminder: off by default; you choose a time in onboarding.
5. Plan **approved**; M0 started.

---

### M0 progress log
- 2026-10-19: Project created with Xcode 16+ folder-synced groups (no third-party generator): `Knock` app, `KnockWidgetsExtension`, local `KnockKit` package (tools 6.4, iOS 27 / macOS 27). App and widget targets use `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + approachable concurrency; `KnockKit` stays nonisolated.
- **SDK verified (27.1 headers):** `static var supportedModes: IntentModes` (`.background`, `.foreground(.immediate | .deferred | .dynamic)`), `continueInForeground(_:alwaysConfirm:)`, `systemContext.currentMode`, `requestChoice(between:dialog:)`, `requestConfirmation(…snippetIntent:)`, `SnippetIntent`. **§3.2 works as designed; no fallback needed.**
- An intent's `perform()` is nonisolated, so intents that touch app state are marked `@MainActor`.
- `swift test` in `KnockKit`: 5 tests / 14 cases pass (`DecimalConversion`, `SpikeProbe`).
- Unsigned device build succeeds; the bundle has the embedded widget, `Metadata.appintents` with the "Log expense in ${applicationName}" phrase, and `MinimumOSVersion = 27.0`.
- 2026-10-20 **device results (free Personal Team, iOS 27):**
  - ✅ **App Groups work on a free account.** The widget read the app's probe and the app read the widget's acknowledgement. **Decision: the shared store lives in the App Group; the §9 fallback isn't needed.**
  - ✅ The intent ran from Siri/Shortcuts with the app closed; the decimal prompt and `requestChoice` behave as designed.
  - ✅ Sheet mode: `continueInForeground` opened the app and presented the sheet.
  - The iOS 27.1 simulator runtime is installed for UI tests.
- **M0 signed off.**

### Verification notes
- **Verified:** installed toolchain and SDK; App Intents snippet APIs (`SnippetIntent`, `Button(intent:)`, `requestConfirmation`) exist since iOS 26 and are unchanged in iOS 27; iOS 27 adds `AppIntentsTesting`, `LongRunningIntent`, `EntityCollection` and `SyncableEntity` (not needed here except testing); App Intents don't require the Siri entitlement.
- **To verify on device / in SDK headers (scheduled in M0/M2):** App Groups on a Personal Team; Back Tap picker behaviour for App Shortcuts on iOS 27; exact `supportedModes` / `continueInForeground` signatures; Control Center buttons running prompting intents in place.
