import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class CaptureRoutingTests: XCTestCase {
    func testCaptureLinksRoundTripOnBothInstallations() {
        for scheme in AppURLScheme.allCases {
            let router = AppURLRouter(scheme: scheme)
            for route in [AppRoute.captureThought(sessionID: nil), .captureThought(sessionID: UUID())] {
                XCTAssertEqual(router.parse(router.url(for: route)), route)
            }
        }
    }

    func testCaptureLinksRejectUnsupportedOrAmbiguousParameters() throws {
        let id = UUID().uuidString
        let suffixes = ["?", "?session", "?session=", "?session=broken", "?project=\(id)",
                        "?session=\(id)&session=\(id)", "?session=\(id)&text=hello", "?session=\(id)#fragment"]
        for scheme in AppURLScheme.allCases {
            let router = AppURLRouter(scheme: scheme)
            for suffix in suffixes {
                let url = try XCTUnwrap(URL(string: "\(scheme.rawValue)://thoughts/new\(suffix)"))
                XCTAssertNil(router.parse(url), url.absoluteString)
            }
            for path in ["", "/", "/new/", "/edit"] {
                XCTAssertNil(router.parse(try XCTUnwrap(URL(string: "\(scheme.rawValue)://thoughts\(path)"))))
            }
            let other: AppURLScheme = scheme == .native ? .container : .native
            XCTAssertNil(router.parse(AppURLRouter(scheme: other).url(for: .captureThought(sessionID: nil))))
        }
    }
}
