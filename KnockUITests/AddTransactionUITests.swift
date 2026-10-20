import XCTest

/// The add / edit / delete flow from PLAN.md §11.1. Runs against a fresh in-memory store.
@MainActor
final class AddTransactionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func logExpense(digits: String, category: String, note: String? = nil, credit: Bool = false) {
        app.buttons["add-button"].tap()
        for key in digits {
            let id = key == "." ? "key-separator" : "key-\(key)"
            app.buttons[id].tap()
        }
        if credit {
            app.descendants(matching: .any)["credit-toggle"].firstMatch.tap()
        }
        app.buttons["category-\(category)"].tap()
        if let note {
            let field = app.textFields["note-field"]
            field.tap()
            field.typeText(note + "\n")
        }
        app.buttons["save-button"].tap()
    }

    func testQuickEntryLogsExpenseAndShowsInHistory() throws {
        app.buttons["add-button"].tap()
        XCTAssertTrue(app.buttons["save-button"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["save-button"].isEnabled, "Save needs an amount and a category")

        for key in ["2", "5", "0", "separator", "5"] {
            app.buttons["key-\(key)"].tap()
        }
        app.buttons["category-Food"].tap()
        attachScreenshot(named: "Quick entry")
        XCTAssertTrue(app.buttons["save-button"].isEnabled)
        app.buttons["save-button"].tap()

        XCTAssertTrue(row(containing: "−₹250.50").waitForExistence(timeout: 3), "Home's recent list shows the new expense")

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(row(containing: "−₹250.50").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Today"].exists)
        attachScreenshot(named: "History")
    }

    func testCreditShowsAsGreenRefund() throws {
        logExpense(digits: "499", category: "Shopping", credit: true)
        XCTAssertTrue(row(containing: "+₹499.00").waitForExistence(timeout: 3))
    }

    func testEditAmountFromHistory() throws {
        logExpense(digits: "120", category: "Transport", note: "Metro")
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.collectionViews["history-list"].waitForExistence(timeout: 3))
        let entryRow = row(containing: "−₹120.00")
        XCTAssertTrue(entryRow.waitForExistence(timeout: 3))
        entryRow.tap()

        let amount = app.textFields["editor-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "Tapping the middle of a row opens the editor")
        amount.tap()
        amount.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
        }
        amount.typeText("180")
        app.buttons["editor-save"].tap()

        XCTAssertTrue(row(containing: "−₹180.00").waitForExistence(timeout: 3))
        XCTAssertFalse(row(containing: "−₹120.00").exists)
    }

    func testSwipeDeleteThenUndo() throws {
        logExpense(digits: "75", category: "Food")
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.collectionViews["history-list"].waitForExistence(timeout: 3))
        let entryRow = row(containing: "−₹75.00")
        XCTAssertTrue(entryRow.waitForExistence(timeout: 3))

        entryRow.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["undo-button"].waitForExistence(timeout: 3))
        XCTAssertFalse(row(containing: "−₹75.00").exists)

        app.buttons["undo-button"].tap()
        XCTAssertTrue(row(containing: "−₹75.00").waitForExistence(timeout: 3))
    }

    /// A row, matched on its combined accessibility label (rows read as one element). Scoped to
    /// History's list once that tab is open, so Home's copy of the same row can't match.
    private func row(containing text: String) -> XCUIElement {
        let history = app.collectionViews["history-list"]
        let scope: XCUIElement = history.exists ? history : app
        return scope.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
