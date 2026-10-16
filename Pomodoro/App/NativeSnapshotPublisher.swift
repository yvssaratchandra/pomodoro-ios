#if NATIVE_INTEGRATIONS
import Foundation
import WidgetKit

@MainActor struct NativeSnapshotPublisher: SnapshotPublishing {
    func publish(_ state: AppSnapshot, now: Date) throws {
        guard let directory = SharedWidgetContainer.directory() else {
            throw AppError.invalid("The shared App Group is unavailable. Check the native app's signing configuration.")
        }
        try WidgetSnapshotFile.write(WidgetSnapshot(state: state, now: now), in: directory)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
