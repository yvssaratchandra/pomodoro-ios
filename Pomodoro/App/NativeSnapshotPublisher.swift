#if NATIVE_INTEGRATIONS
import Foundation
import WidgetKit

@MainActor struct NativeSnapshotPublisher: SnapshotPublishing {
    func publish(_ state: AppSnapshot, now: Date) throws {
        guard let directory = SharedWidgetContainer.directory() else {
            throw AppError.invalid("Widget storage is unavailable for this installation.")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = Statistics.today(now, calendar: calendar)
        let summary = WidgetSnapshot.SavedFocus(dayStart: day.start, dayEnd: day.end,
            timeZoneIdentifier: calendar.timeZone.identifier,
            seconds: Statistics.total(state, interval: day, now: now))
        try WidgetSnapshotFile.write(WidgetSnapshot(state: state, now: now, savedFocus: summary), in: directory)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
