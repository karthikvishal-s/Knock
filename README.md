# Knock

Log an expense or income in under three seconds: **double-tap the back of your iPhone**, type the amount, pick a category, done. Knock never needs to open. Inside the app you get history, accounts, budgets, recurring bills, savings goals and Swift Charts analytics.

Personal project. All data stays on the device: no account, no analytics, no ads.

## Status

| Milestone | Scope | State |
|---|---|---|
| M0 | Project setup, App Group + App Intents spikes | ✅ Verified on device |
| M1 | Data model, add/edit/delete, History with search & filters | ✅ |
| M2 | Back Tap / Siri quick-log intents, confirmation snippet, setup guide | ✅ (Back Tap needs on-device QA) |
| M3 | Accounts, transfers, income, category management, tags, receipts | ✅ |
| M4 | Analytics (dashboard, categories, trends, year, heatmap, net worth) | ✅ |
| M5 | Budgets with rollover & safe-to-spend, recurring, reminders, goals | ✅ |
| M6 | Home & Lock Screen widgets, Control Center controls | ✅ (needs on-device QA) |
| M7 | CSV import/export, JSON backup/restore, auto-backup, App Lock | ✅ |
| M8 | 20k-row performance, accessibility sizes, app icon | ✅ |

Tests: 111 unit tests (`KnockKit`) + 6 UI tests. The full design is in [PLAN.md](PLAN.md).

## Requirements

- Xcode 27.1+ (Swift 6.4, iOS 27 SDK)
- iPhone on iOS 27
- An Apple ID. A free Personal Team works, but **the app must be re-run from Xcode every 7 days**. Your data is kept as long as you don't delete the app.

## Build & run

1. Open `Knock.xcodeproj`.
2. Under **Signing & Capabilities**, set your Team for the `Knock`, `KnockWidgetsExtension` and `KnockUITests` targets.
3. Choose your iPhone (Developer Mode on) and press **Run**.

## Using Knock

### Back Tap (the main feature)
1. **Shortcuts** app → **＋** → **Add Action** → search **Knock** → **Log Expense** → name it "Log Expense". Repeat for **Log Income**.
2. **Settings → Accessibility → Touch → Back Tap → Double Tap → Log Expense**; **Triple Tap → Log Income**.
3. Double-tap the back of your phone: amount → category → saved. The confirmation card has **Undo** and **Edit**.

The in-app guide (Settings → Set up Back Tap) walks through this and confirms when it works. Prefer the big keypad? Settings → Capture → "App keypad".

### Siri
- "Log expense in Knock" · "Add income in Knock" · "Quick log in Knock"
- "Repeat last in Knock" · "How much did I spend in Knock"

### Widgets & controls
- **Home Screen:** *Quick Log* (Expense / Income buttons) and *This Month* (small, medium, large).
- **Lock Screen:** budget ring, spending line and inline "₹… safe today".
- **Control Center:** *Log Expense* and *Log Income* buttons (they open the keypad).

### Backups
- Knock writes a JSON backup every day you open it and keeps the last 14: **Files → On My iPhone → Knock → Backups**.
- **Settings → Export, import & backup** has CSV export, CSV import from other apps or bank statements (with column matching), and full backup/restore.

## Project layout

```
Knock/            iOS app: SwiftUI screens, App Intents, notifications, App Lock
KnockWidgets/     Widget extension: Home/Lock Screen widgets, Control Center controls
KnockKit/         Swift package: SwiftData models, services, analytics, import/export
KnockUITests/     UI tests and screenshot walkthroughs
Config/           Entitlements and Info.plists
```

## Tests

```sh
cd KnockKit && swift test        # 111 domain, persistence, analytics and 20k-row performance tests
```

UI tests: run the `Knock` scheme's tests in Xcode, or:

```sh
xcodebuild -project Knock.xcodeproj -scheme Knock -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KnockUITests test
```
