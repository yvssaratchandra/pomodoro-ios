import SwiftUI
import UIKit

/// Observes touches without taking touches away from SwiftUI controls or scrolling.
struct FocusInteractionObserver: UIViewRepresentable {
    var enabled: Bool
    var onBegin: () -> Void
    var onEnd: () -> Void

    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ view: ObserverView, context: Context) {
        view.onBegin = onBegin
        view.onEnd = onEnd
        view.enabled = enabled
        view.refresh()
    }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var enabled = false
        var onBegin: (() -> Void)?
        var onEnd: (() -> Void)?
        private var observing = false
        private var finishTask: Task<Void, Never>?
        private weak var scrollView: UIScrollView?
        private lazy var recognizer: TouchObserver = {
            let recognizer = TouchObserver(target: self, action: #selector(touchChanged))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()

        override func didMoveToWindow() { super.didMoveToWindow(); refresh() }
        func refresh() {
            guard enabled, let window else { detach(); return }
            if recognizer.view !== window {
                recognizer.view?.removeGestureRecognizer(recognizer)
                window.addGestureRecognizer(recognizer)
            }
        }
        func detach() {
            finishTask?.cancel()
            recognizer.view?.removeGestureRecognizer(recognizer)
            finishObservation()
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard enabled, let window, touch.window === window,
                  bounds.contains(touch.location(in: self)),
                  window.rootViewController?.presentedViewController == nil else { return false }
            var ancestor = touch.view
            while let current = ancestor {
                if let scroll = current as? UIScrollView { scrollView = scroll; break }
                ancestor = current.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func touchChanged() {
            switch recognizer.state {
            case .began:
                finishTask?.cancel()
                if !observing { observing = true; onBegin?() }
            case .ended, .cancelled, .failed:
                finishTask?.cancel()
                finishTask = Task { @MainActor [weak self] in
                    // UIKit starts deceleration after delivering the final touch event.
                    await Task.yield()
                    while let scroll = self?.scrollView, scroll.isDragging || scroll.isDecelerating || scroll.isTracking {
                        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    }
                    guard !Task.isCancelled else { return }
                    self?.finishObservation()
                }
            default: break
            }
        }
        private func finishObservation() {
            scrollView = nil
            if observing { observing = false; onEnd?() }
        }
    }

    final class TouchObserver: UIGestureRecognizer {
        private var touches: Set<UITouch> = []
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            self.touches.formUnion(touches)
            state = state == .possible ? .began : .changed
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { state = .changed }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            self.touches.subtract(touches)
            state = self.touches.isEmpty ? .ended : .changed
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
        override func reset() { super.reset(); touches.removeAll() }
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}
