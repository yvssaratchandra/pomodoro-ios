import SwiftUI
import UIKit

struct FocusMenuAction {
    var title: String
    var systemImage: String
    var destructive = false
    var identifier: String? = nil
    var action: () -> Void
}

/// A native menu button reports its actual presentation lifecycle to Dim Focus.
struct FocusMenuButton: UIViewRepresentable {
    var actions: [FocusMenuAction]
    var onPresentationChange: (Bool) -> Void

    func makeUIView(context: Context) -> LifecycleMenuButton {
        let button = LifecycleMenuButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        button.accessibilityLabel = "More"
        button.accessibilityIdentifier = "focus.more"
        button.showsMenuAsPrimaryAction = true
        return button
    }

    func updateUIView(_ button: LifecycleMenuButton, context: Context) {
        button.presentationChanged = onPresentationChange
        let menu = UIMenu(children: actions.map { item in
            UIAction(title: item.title, image: UIImage(systemName: item.systemImage),
                     identifier: item.identifier.map { UIAction.Identifier($0) },
                     attributes: item.destructive ? .destructive : []) { _ in item.action() }
        })
        if button.menuVisible { button.pendingMenu = menu }
        else { button.menu = menu }
    }

    static func dismantleUIView(_ button: LifecycleMenuButton, coordinator: ()) {
        if button.menuVisible { button.presentationChanged?(false) }
    }

    final class LifecycleMenuButton: UIButton {
        var presentationChanged: ((Bool) -> Void)?
        var menuVisible = false
        var pendingMenu: UIMenu?

        override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                            willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                            animator: UIContextMenuInteractionAnimating?) {
            super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
            menuVisible = true
            presentationChanged?(true)
        }

        override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                            willEndFor configuration: UIContextMenuConfiguration,
                                            animator: UIContextMenuInteractionAnimating?) {
            super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
            if let animator {
                animator.addCompletion { [weak self] in self?.finishDismissal() }
            } else { finishDismissal() }
        }

        private func finishDismissal() {
            menuVisible = false
            if let pendingMenu {
                menu = pendingMenu
                self.pendingMenu = nil
            }
            presentationChanged?(false)
        }
    }
}
