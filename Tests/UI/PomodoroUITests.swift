import XCTest

final class PomodoroUITests: XCTestCase {
    func testURLProjectCreationAndTimerRecoveryAcrossRelaunch() {
        continueAfterFailure = false
        let app = newApp()
        app.launchEnvironment["POMODORO_TEST_STORE_ID"] = UUID().uuidString
        app.open(URL(string: "pomodoro://projects/new")!)
        let name = app.textFields["project.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Linked project")
        app.buttons["project.save"].tap()
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Stats"].tap()
        // open(_:) relaunches the process and exercises durable timer recovery.
        app.open(URL(string: "pomodoro://timer")!)
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Focus"].isSelected)
        app.open(URL(string: "pomodoro://focus?project=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA&action=start")!)
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Linked project"].firstMatch.exists)
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Discard Session"].tap()
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["No sessions in this selection"].waitForExistence(timeout: 5))
    }

    func testQuickStartSetupShowsInvalidURLAndCreatesShortcutWithoutStarting() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.quickstart"].tap()
        let toggle = app.switches["quickstart.useContainer"]
        if toggle.exists {
            if toggle.value as? String == "0" { toggle.tap() }
            let field = app.textFields["quickstart.launchURL"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            replaceText(in: field, with: "https://example.com")
            XCTAssertTrue(app.staticTexts["quickstart.invalidURL"].waitForExistence(timeout: 5))
            replaceText(in: field, with: "livecontainer2://livecontainer-launch?bundle-name=Pomodoro.app&container-folder-name=test")
        }
        let copy = app.buttons["quickstart.copy"]
        reveal(copy, in: app, scrollingUp: true)
        XCTAssertTrue(copy.isEnabled)
        copy.tap()
        XCTAssertTrue(app.staticTexts["quickstart.copied"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Focus"].tap()
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["timer.countdown"].exists)
    }

    func testCreateFocusEndAndReviewSession() {
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        app.tabBars.buttons["Focus"].tap()
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Save Session"].tap()
        app.tabBars.buttons["Stats"].tap()
        let session = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertTrue(session.label.contains("Writing"))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    func testDurationWheelRemembersProjectAndRunningTimerIsReadOnly() {
        continueAfterFailure = false
        let app = newApp()
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
        attachScreenshot("Focus ready", app: app)
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["focus.duration"].exists)
        attachScreenshot("Focus running", app: app)
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Save Session"].tap()
        assertDuration("40 min", in: app)
        chooseProject("Study", in: app)
        assertDuration("15 min", in: app)
    }

    func testDiscardAndImmediateHistoryDeletionUndo() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        app.tabBars.buttons["Focus"].tap()
        app.buttons["focus.start"].tap()
        app.buttons["timer.end"].tap()
        let endAlert = app.alerts["End focus?"]
        XCTAssertTrue(endAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(endAlert.buttons["Save Session"].exists)
        XCTAssertTrue(endAlert.buttons["Discard Session"].exists)
        endAlert.buttons["Keep Focusing"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].exists)
        app.buttons["timer.end"].tap()
        endAlert.buttons["Discard Session"].tap()
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["No sessions in this selection"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Focus"].tap()
        app.buttons["focus.start"].tap()
        app.buttons["timer.end"].tap()
        endAlert.buttons["Save Session"].tap()
        app.tabBars.buttons["Stats"].tap()
        let session = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.swipeLeft()
        if app.buttons["Delete"].exists { app.buttons["Delete"].tap() }
        XCTAssertFalse(session.exists)
        let undo = app.buttons["session.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(session.waitForExistence(timeout: 5))
    }

    func testSessionNoteThoughtBreadcrumbAndStatistics() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        app.tabBars.buttons["Focus"].tap()
        app.buttons["focus.intention"].tap()
        enterText("Draft introduction", into: "intention.text", in: app)
        app.buttons["intention.save"].tap()
        app.buttons["focus.start"].tap()
        let capture = app.buttons["focus.captureThought"]
        reveal(capture, in: app, scrollingUp: false)
        capture.tap()
        enterText("Find the source later", into: "thought.text", in: app)
        app.buttons["thought.save"].tap()
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Save Session"].tap()
        let next = app.buttons["focus.nextStep"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        enterText("Continue with methods", into: "breadcrumb.text", in: app)
        app.buttons["breadcrumb.save"].tap()
        app.tabBars.buttons["Stats"].tap()
        let session = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertTrue(session.label.contains("Draft introduction"))
        app.buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["Focus time"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Thoughts"].tap()
        let check = app.buttons["thought.check"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertEqual(check.value as? String, "Open")
        check.tap()
        XCTAssertEqual(check.value as? String, "Done")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(check.exists)
        check.tap()
        XCTAssertTrue(app.staticTexts["No matching thoughts"].waitForExistence(timeout: 5))
        app.buttons["Open"].tap()
        XCTAssertTrue(check.waitForExistence(timeout: 5))
    }

    func testStandaloneThoughtSearchUnassignedCheckDeleteAndUndo() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        app.tabBars.buttons["Thoughts"].tap()
        app.buttons["thoughts.new"].tap()
        enterText("Review bibliography", into: "thought.text", in: app)
        app.buttons["thought.save"].tap()
        let thought = app.staticTexts["Review bibliography"].firstMatch
        XCTAssertTrue(thought.waitForExistence(timeout: 5))
        let project = app.buttons["thoughts.project"]
        project.tap()
        app.buttons["Unassigned"].tap()
        XCTAssertTrue(thought.exists)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("bibliography")
        XCTAssertTrue(thought.exists)
        replaceText(in: search, with: "missing")
        XCTAssertTrue(app.staticTexts["No matching thoughts"].waitForExistence(timeout: 5))
        reveal(app.buttons["Clear filters"], in: app)
        app.buttons["Clear filters"].tap()
        XCTAssertTrue(thought.waitForExistence(timeout: 5))
        let check = app.buttons["thought.check"].firstMatch
        check.tap()
        XCTAssertEqual(check.value as? String, "Done")
        thought.swipeLeft()
        if app.buttons["Delete"].exists { app.buttons["Delete"].tap() }
        XCTAssertFalse(thought.exists)
        let undo = app.buttons["session.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(thought.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["thought.check"].firstMatch.value as? String, "Done")
    }

    func testVisualStatesLightDarkAndAccessibilityText() {
        continueAfterFailure = false
        for (name, appearance, textSize) in [
            ("Light", "light", "standard"),
            ("Dark", "dark", "standard"),
            ("Large text", "dark", "accessibility2")
        ] {
            let app = newApp()
            app.launchEnvironment["POMODORO_TEST_APPEARANCE"] = appearance
            app.launchEnvironment["POMODORO_TEST_DYNAMIC_TYPE"] = textSize
            app.launch()
            createProject("A long project name for layout checks", in: app)
            app.tabBars.buttons["Focus"].tap()
            XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
            if textSize == "standard" {
                XCTAssertTrue(app.buttons["focus.start"].isHittable)
                XCTAssertTrue(app.buttons["focus.duration"].isHittable)
            }
            attachScreenshot("\(name) · Focus ready", app: app)
            reveal(app.buttons["focus.start"], in: app)
            app.buttons["focus.start"].tap()
            XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
            attachScreenshot("\(name) · Focus running", app: app)
            app.buttons["focus.captureThought"].tap()
            enterText("A thought saved during focus", into: "thought.text", in: app)
            app.buttons["thought.save"].tap()
            app.buttons["timer.end"].tap()
            app.alerts["End focus?"].buttons["Save Session"].tap()
            attachScreenshot("\(name) · Focus after saving", app: app)
            app.tabBars.buttons["Stats"].tap()
            attachScreenshot("\(name) · Stats", app: app)
            app.tabBars.buttons["Thoughts"].tap()
            attachScreenshot("\(name) · Thoughts", app: app)
            app.tabBars.buttons["Settings"].tap()
            attachScreenshot("\(name) · Settings", app: app)
            app.terminate()
            let breakApp = newApp()
            breakApp.launchEnvironment["POMODORO_TEST_SCENARIO"] = "break-ready"
            breakApp.launchEnvironment["POMODORO_TEST_APPEARANCE"] = appearance.lowercased()
            if name == "Large text" { breakApp.launchEnvironment["POMODORO_TEST_DYNAMIC_TYPE"] = "accessibility2" }
            breakApp.launch()
            let startBreak = breakApp.buttons["Start Break"]
            XCTAssertTrue(startBreak.waitForExistence(timeout: 5))
            attachScreenshot("\(name) · Break ready", app: breakApp)
            reveal(startBreak, in: breakApp)
            startBreak.tap()
            XCTAssertTrue(breakApp.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
            attachScreenshot("\(name) · Break running", app: breakApp)
            breakApp.terminate()
        }
    }

    private func newApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--disable-notifications"]
        return app
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

    private func enterText(_ value: String, into identifier: String, in app: XCUIApplication) {
        let text = app.textFields[identifier].exists ? app.textFields[identifier] : app.textViews[identifier]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText(value)
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        field.typeText(value)
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
