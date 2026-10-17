import UIKit

@MainActor enum PresentationAvailability {
    static var hasPresentedContent: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .filter(\.isKeyWindow)
            .contains { window in
                guard let root = window.rootViewController else { return false }
                return hasPresentation(root)
            }
    }

    private static func hasPresentation(_ controller: UIViewController) -> Bool {
        if controller.presentedViewController != nil { return true }
        return controller.children.contains(where: hasPresentation)
    }
}
