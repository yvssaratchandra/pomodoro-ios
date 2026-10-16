import XCTest

final class PomodoroUITests: XCTestCase {
    func testCreateFocusEndAndReviewInterruptedSession() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--disable-notifications"]
        app.launch()
        app.tabBars.buttons["Projects"].tap()
        app.buttons["projects.new"].tap()
        let field = app.textFields["project.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Writing")
        app.buttons["project.save"].tap()
        app.tabBars.buttons["Focus"].tap()
        reveal(app.buttons["focus.start"], in: app)
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        app.buttons["timer.end"].tap()
        app.buttons["End and Save Work"].tap()
        app.tabBars.buttons["Stats"].tap()
        let interrupted = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(interrupted.waitForExistence(timeout: 5))
        XCTAssertTrue(interrupted.label.contains("Writing"))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    func testDurationWheelStaysSelectedAndProjectsRememberTheirChoices() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--disable-notifications"]
        app.launch()
        createProject("Writing", in: app)
        createProject("Study", in: app)
        app.tabBars.buttons["Focus"].tap()
        chooseProject("Writing", in: app)
        setDuration("40 min", in: app)
        assertDuration("40 min", in: app)

        app.tabBars.buttons["Stats"].tap()
        app.tabBars.buttons["Focus"].tap()
        assertDuration("40 min", in: app)
        chooseProject("Study", in: app)
        assertDuration("25 min", in: app)
        setDuration("15 min", in: app)
        chooseProject("Writing", in: app)
        assertDuration("40 min", in: app)
        setDuration("50 min", in: app, save: false)
        assertDuration("40 min", in: app)
        chooseProject("Study", in: app)
        assertDuration("15 min", in: app)
        chooseProject("Writing", in: app)

        reveal(app.buttons["focus.start"], in: app, scrollingUp: false)
        attachScreenshot("Focus ready", app: app)
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        // Edit the next session while the countdown is refreshing every second.
        setDuration("35 min", in: app)
        assertDuration("35 min", in: app)
        reveal(app.buttons["timer.end"], in: app, scrollingUp: false)
        let countdown = app.staticTexts["timer.countdown"]
        let remaining = countdown.value as? String ?? ""
        let remainingMinutes = Int(remaining.split(separator: " ").first ?? "") ?? 0
        XCTAssertTrue((36...40).contains(remainingMinutes), remaining)
        attachScreenshot("Focus running", app: app)
        app.buttons["timer.end"].tap()
        app.buttons["End and Save Work"].tap()
        assertDuration("35 min", in: app)
    }

    func testDiscardAndConfirmedHistoryDeletion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--disable-notifications"]
        app.launch()
        createProject("Writing", in: app)
        app.tabBars.buttons["Focus"].tap()
        app.buttons["focus.start"].tap()
        app.buttons["timer.end"].tap()
        app.buttons["Keep Focusing"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].exists)
        app.buttons["timer.end"].tap()
        app.buttons["Discard Session"].tap()
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["No Focus Yet"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Focus"].tap()
        app.buttons["focus.start"].tap()
        app.buttons["timer.end"].tap()
        app.buttons["End and Save Work"].tap()
        app.tabBars.buttons["Stats"].tap()
        app.buttons["All history"].tap()
        let session = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.swipeLeft()
        app.buttons["Delete"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(session.exists)
        if !app.buttons["Delete"].isHittable { session.swipeLeft() }
        app.buttons["Delete"].tap()
        app.buttons["Delete Session"].tap()
        XCTAssertTrue(app.staticTexts["No Focus Yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(session.exists)
    }

    private func createProject(_ name: String, in app: XCUIApplication) {
        app.tabBars.buttons["Projects"].tap()
        app.buttons["projects.new"].tap()
        let field = app.textFields["project.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["project.save"].tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool = true) {
        for _ in 0..<5 {
            if element.isHittable { return }
            if scrollingUp { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func chooseProject(_ name: String, in app: XCUIApplication) {
        let picker = app.buttons["focus.project"]
        reveal(picker, in: app)
        picker.tap()
        app.buttons[name].tap()
    }

    private func setDuration(_ value: String, in app: XCUIApplication, save: Bool = true) {
        let button = app.buttons["focus.duration"]
        reveal(button, in: app)
        button.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        wheel.adjust(toPickerWheelValue: value)
        // Explicitly cover the reported delayed reset, spanning multiple refreshes.
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", value), object: wheel)
        changed.isInverted = true
        wait(for: [changed], timeout: 3)
        XCTAssertEqual(wheel.value as? String, value)
        app.buttons[save ? "focus.duration.done" : "focus.duration.cancel"].tap()
    }

    private func assertDuration(_ value: String, in app: XCUIApplication) {
        let button = app.buttons["focus.duration"]
        reveal(button, in: app)
        XCTAssertEqual(button.value as? String, value)
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
