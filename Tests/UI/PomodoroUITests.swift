import XCTest

final class PomodoroUITests: XCTestCase {
    func testURLProjectCreationAndTimerRecoveryAcrossRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--disable-notifications"]
        app.launchEnvironment["POMODORO_TEST_STORE_ID"] = UUID().uuidString
        app.open(URL(string: "pomodoro://projects/new")!)
        let name = app.textFields["project.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Linked project")
        app.buttons["project.save"].tap()
        let start = app.buttons["focus.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Stats"].tap()
        // open(_:) relaunches the process, so this also exercises durable timer recovery.
        app.open(URL(string: "pomodoro://timer")!)
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Focus"].isSelected)
        app.open(URL(string: "pomodoro://focus?project=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA&action=start")!)
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Linked project"].firstMatch.exists)
        app.buttons["timer.end"].tap()
        app.alerts["End this focus session?"].buttons["Discard Session"].tap()
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["No Focus Yet"].waitForExistence(timeout: 5))
    }

    func testQuickStartSetupShowsInvalidURLAndCreatesShortcutWithoutStarting() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--disable-notifications"]
        app.launch()
        createProject("Writing", in: app)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.quickstart"].tap()
        let toggle = app.switches["quickstart.useContainer"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String == "0" { toggle.tap() }
        let field = app.textFields["quickstart.launchURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        field.typeText("https://example.com")
        XCTAssertTrue(app.staticTexts["quickstart.invalidURL"].waitForExistence(timeout: 5))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "https://example.com".count))
        field.typeText("livecontainer2://livecontainer-launch?bundle-name=Pomodoro.app&container-folder-name=test")
        app.swipeUp()
        let copy = app.buttons["quickstart.copy"]
        reveal(copy, in: app, scrollingUp: true)
        XCTAssertTrue(copy.isEnabled)
        copy.tap()
        XCTAssertTrue(app.staticTexts["quickstart.copied"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Focus"].tap()
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["timer.countdown"].exists)
    }

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
        let endAlert = app.alerts["End this focus session?"]
        XCTAssertTrue(endAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(endAlert.buttons["End and Save Work"].exists)
        XCTAssertTrue(endAlert.buttons["Discard Session"].exists)
        endAlert.buttons["Keep Focusing"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: endAlert)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["timer.countdown"].exists)
        app.buttons["timer.end"].tap()
        XCTAssertTrue(endAlert.waitForExistence(timeout: 5))
        endAlert.buttons["Discard Session"].tap()
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
        let deleteAlert = app.alerts["Delete this session?"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 5))
        deleteAlert.buttons["Cancel"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: deleteAlert)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(session.exists)
        if !app.buttons["Delete"].isHittable { session.swipeLeft() }
        app.buttons["Delete"].tap()
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 5))
        deleteAlert.buttons["Delete Session"].tap()
        XCTAssertTrue(app.staticTexts["No Focus Yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(session.exists)
    }

    func testIntentionCaptureBreadcrumbUndoAndThoughtChecklist() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--disable-notifications"]
        app.launch()
        createProject("Writing", in: app)
        app.tabBars.buttons["Focus"].tap()
        app.buttons["focus.start"].tap()
        let intention = app.buttons["focus.intention.edit"]
        reveal(intention, in: app)
        intention.tap()
        let intentionText = app.textViews["intention.text"].exists ? app.textViews["intention.text"] : app.textFields["intention.text"]
        XCTAssertTrue(intentionText.waitForExistence(timeout: 5))
        intentionText.tap()
        intentionText.typeText("Draft introduction")
        app.buttons["intention.save"].tap()
        let capture = app.buttons["focus.captureThought"]
        reveal(capture, in: app, scrollingUp: false)
        capture.tap()
        let text = app.textViews["thought.text"].exists ? app.textViews["thought.text"] : app.textFields["thought.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("Find the source later")
        app.buttons["thought.save"].tap()
        reveal(app.buttons["timer.end"], in: app, scrollingUp: false)
        app.buttons["timer.end"].tap()
        app.alerts.buttons["End and Save Work"].tap()
        let next = app.buttons["focus.nextStep"]
        reveal(next, in: app)
        next.tap()
        let note = app.textViews["breadcrumb.text"].exists ? app.textViews["breadcrumb.text"] : app.textFields["breadcrumb.text"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("Continue with methods")
        app.buttons["breadcrumb.save"].tap()
        app.tabBars.buttons["Stats"].tap()
        let session = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertTrue(session.label.contains("Draft introduction"))
        session.swipeLeft()
        app.buttons["Delete"].tap()
        app.alerts["Delete this session?"].buttons["Delete Session"].tap()
        let undo = app.buttons["session.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        app.buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["Total focus"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Thoughts"].tap()
        let check = app.buttons["thought.check"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertEqual(check.value as? String, "Open")
        check.tap()
        XCTAssertEqual(check.value as? String, "Done")
        app.buttons["Done"].tap()
        XCTAssertTrue(check.exists)
        check.tap()
        XCTAssertTrue(app.staticTexts["No Thoughts"].waitForExistence(timeout: 5))
        app.buttons["Open"].tap()
        XCTAssertTrue(check.waitForExistence(timeout: 5))
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
