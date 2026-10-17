import UIKit

@MainActor enum PresentationAvailability {
    static func hasPresentedContent(in controller: UIViewController) -> Bool {
        if controller.presentedViewController != nil { return true }
        // Only inspect the app's own subtree. Its parent or presenting controller
        // may belong to the container that is hosting the app.
        return controller.children.contains { hasPresentedContent(in: $0) }
    }
}
