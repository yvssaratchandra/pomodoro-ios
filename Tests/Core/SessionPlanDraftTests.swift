import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class SessionPlanDraftTests: XCTestCase {
    private struct SaveFailure: Error {}

    func testInitializationContainsOnlyAcceptedTasks() {
        XCTAssertTrue(SessionPlanDraft(text: " \n ").rows.isEmpty)
        let draft = SessionPlanDraft(text: " First\n\nSecond ")
        XCTAssertEqual(draft.rows.map(\.text), ["First", "Second"])
    }

    func testBlankAddNeverCallsCommit() {
        var draft = SessionPlanDraft(text: "First")
        let original = draft.rows
        XCTAssertThrowsError(try draft.apply(.add(" \r\n \t")) { _ in
            XCTFail("Blank additions must not be committed")
            return .success(())
        })
        XCTAssertEqual(draft.rows, original)
    }

    func testMultilineAddIsNormalizedAndCommittedTogether() throws {
        var draft = SessionPlanDraft(text: "Before")
        let firstID = draft.rows[0].id
        var commits: [String] = []
        let destination = try draft.apply(.add(" One\r\n \r\nTwo\rThree\n")) {
            commits.append($0)
            return .success(())
        }
        XCTAssertEqual(commits, ["Before\nOne\nTwo\nThree"])
        XCTAssertEqual(draft.rows.map(\.text), ["Before", "One", "Two", "Three"])
        XCTAssertEqual(draft.rows[0].id, firstID)
        XCTAssertEqual(destination, draft.rows.last?.id)
    }

    func testFailedMutationsPreserveAcceptedRowsAndIDs() {
        var draft = SessionPlanDraft(text: "First\nSecond")
        let original = draft.rows
        for mutation in [SessionPlanDraft.Mutation.add("Third"), .edit(original[0].id, "Changed\nExtra"), .delete(original[1].id)] {
            XCTAssertThrowsError(try draft.apply(mutation) { _ in .failure(SaveFailure()) })
            XCTAssertEqual(draft.rows, original)
        }
    }

    func testEditKeepsTargetAndUnaffectedIDsWhenSplitting() throws {
        var draft = SessionPlanDraft(text: "First\nLast")
        let original = draft.rows
        try draft.apply(.edit(original[0].id, " Changed\n\nAdditional ")) { text in
            XCTAssertEqual(text, "Changed\nAdditional\nLast")
            return .success(())
        }
        XCTAssertEqual(draft.rows.map(\.text), ["Changed", "Additional", "Last"])
        XCTAssertEqual(draft.rows[0].id, original[0].id)
        XCTAssertEqual(draft.rows[2].id, original[1].id)
        XCTAssertFalse(original.map(\.id).contains(draft.rows[1].id))
    }

    func testBlankEditRequiresExplicitDeletion() {
        var draft = SessionPlanDraft(text: "First")
        let original = draft.rows
        XCTAssertThrowsError(try draft.apply(.edit(original[0].id, " \n")) { _ in
            XCTFail("Blank edits must not be committed")
            return .success(())
        })
        XCTAssertEqual(draft.rows, original)
    }

    func testDeletingLastTaskCommitsEmptyIntention() throws {
        var draft = SessionPlanDraft(text: "Only task")
        try draft.apply(.delete(draft.rows[0].id)) { text in
            XCTAssertEqual(text, "")
            return .success(())
        }
        XCTAssertTrue(draft.rows.isEmpty)
    }

    func testCombinedLimitCountsSeparatorsAndSwiftCharacters() throws {
        var draft = SessionPlanDraft(text: String(repeating: "a", count: 139))
        let original = draft.rows
        let candidate = try draft.candidate(for: .add(String(repeating: "🧠", count: 140)))
        XCTAssertEqual(candidate.text.count, 280)
        XCTAssertEqual(draft.rows, original, "Validation must not adopt a candidate")
        XCTAssertThrowsError(try draft.apply(.add(String(repeating: "🧠", count: 141))) { _ in
            XCTFail("Overlong additions must not be committed")
            return .success(())
        })
        XCTAssertEqual(draft.rows, original)
        try draft.apply(.add(String(repeating: "🧠", count: 140))) { _ in .success(()) }
        XCTAssertEqual(draft.characterCount, 280)
        XCTAssertThrowsError(try draft.candidate(for: .edit(draft.rows[0].id, String(repeating: "a", count: 140))))
    }

    func testReconciliationPreservesSurvivingDuplicateIDsInOrder() {
        var draft = SessionPlanDraft(text: "Same\nRemove\nSame\nLast")
        let original = draft.rows
        draft.reconcile(text: "Last\nSame\nNew\nSame")
        XCTAssertEqual(draft.rows.map(\.text), ["Last", "Same", "New", "Same"])
        XCTAssertEqual(draft.rows[0].id, original[3].id)
        XCTAssertEqual(draft.rows[1].id, original[0].id)
        XCTAssertEqual(draft.rows[3].id, original[2].id)
        XCTAssertFalse(original.map(\.id).contains(draft.rows[2].id))
    }

    func testStaleTargetCannotEditAnotherTask() {
        var draft = SessionPlanDraft(text: "Original")
        let removedID = draft.rows[0].id
        draft.reconcile(text: "Replacement")
        for mutation in [SessionPlanDraft.Mutation.edit(removedID, "Changed"), .delete(removedID)] {
            XCTAssertThrowsError(try draft.apply(mutation) { _ in
                XCTFail("A stale target must not be committed")
                return .success(())
            })
        }
        XCTAssertEqual(draft.rows.map(\.text), ["Replacement"])
    }
}
