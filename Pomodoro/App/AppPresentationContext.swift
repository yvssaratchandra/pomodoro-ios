import SwiftUI
import UIKit

@MainActor final class AppPresentationContext: ObservableObject {
    @Published private(set) var isActive = false
    private weak var anchor: UIViewController?
    private var isVisible = false
    private var applicationIsInactive = false

    var hasPresentedContent: Bool {
        guard let anchor else { return true }
        return PresentationAvailability.hasPresentedContent(in: anchor.parent ?? anchor)
    }

    var canPresent: Bool { isActive && !hasPresentedContent }

    func attach(_ controller: UIViewController, visible: Bool) {
        anchor = controller
        isVisible = visible
        refresh()
    }

    func applicationBecameActive() {
        applicationIsInactive = false
        refresh()
    }

    func applicationResignedActive() {
        applicationIsInactive = true
        if isActive { isActive = false }
    }

    func refresh() {
        let window = anchor?.viewIfLoaded?.window
        let foreground: Bool
        if let scene = window?.windowScene {
            foreground = scene.activationState == .foregroundActive
        } else {
            #if NATIVE_INTEGRATIONS
            foreground = false
            #else
            // Some hosted app windows do not own a scene connection.
            foreground = window?.isKeyWindow == true && UIApplication.shared.applicationState == .active
            #endif
        }
        let active = !applicationIsInactive && isVisible && window != nil && window?.isHidden == false && foreground
        if isActive != active { isActive = active }
    }
}

struct AppPresentationProbe: UIViewControllerRepresentable {
    let context: AppPresentationContext

    func makeUIViewController(context: Context) -> ProbeController {
        ProbeController(presentation: self.context)
    }

    func updateUIViewController(_ controller: ProbeController, context: Context) {}

    final class ProbeController: UIViewController {
        private weak var presentation: AppPresentationContext?

        init(presentation: AppPresentationContext) {
            self.presentation = presentation
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("Use init(presentation:)") }

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentation?.attach(self, visible: true)
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            presentation?.attach(self, visible: false)
        }
    }
}
