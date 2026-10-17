import XCTest
import UIKit
@testable import Pomodoro

@MainActor final class PresentationAvailabilityTests: XCTestCase {
    func testContainerPresentationDoesNotBlockGuestContent() {
        let host = PresentationController()
        let guest = UIViewController()
        host.addChild(guest)
        host.overlay = UIViewController()
        XCTAssertTrue(PresentationAvailability.hasPresentedContent(in: host))
        XCTAssertFalse(PresentationAvailability.hasPresentedContent(in: guest))
    }

    func testOwnNestedEditorBlocksPresentationUntilDismissed() {
        let guest = UIViewController()
        let child = PresentationController()
        guest.addChild(child)
        child.overlay = UIViewController()
        XCTAssertTrue(PresentationAvailability.hasPresentedContent(in: guest))
        child.overlay = nil
        XCTAssertFalse(PresentationAvailability.hasPresentedContent(in: guest))
    }
}

private final class PresentationController: UIViewController {
    var overlay: UIViewController?
    override var presentedViewController: UIViewController? { overlay }
}
