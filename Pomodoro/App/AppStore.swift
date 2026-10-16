import SwiftUI
import SwiftData
import UserNotifications
import Observation

@MainActor @Observable final class AppStore {
    private(set) var state: AppSnapshot
    var errorMessage: String?
    private let persistence: any SnapshotPersistence
    private let now: () -> Date
    private let publisher: any SnapshotPublishing
    private let liveActivities: any LiveActivityManaging
    private let notificationCenter: any TimerNotificationCenter
    @ObservationIgnored private var activityTask: Task<Void, Never>?
    @ObservationIgnored private var activityGeneration: UInt64 = 0

    convenience init(container: ModelContainer) throws {
        try self.init(persistence: SwiftDataSnapshotPersistence(container: container))
    }

    init(persistence: any SnapshotPersistence,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current,
         publisher: (any SnapshotPublishing)? = nil,
         liveActivities: (any LiveActivityManaging)? = nil,
         notificationCenter: (any TimerNotificationCenter)? = nil) throws {
        self.persistence = persistence
        self.now = now
        #if NATIVE_INTEGRATIONS
        self.publisher = publisher ?? NativeSnapshotPublisher()
        #else
        self.publisher = publisher ?? NoOpSnapshotPublisher()
        #endif
        #if NATIVE_INTEGRATIONS
        self.liveActivities = liveActivities ?? NativeLiveActivityManager()
        #else
        self.liveActivities = liveActivities ?? NoOpLiveActivityManager()
        #endif
        self.notificationCenter = notificationCenter ?? SystemTimerNotificationCenter()
        if let payload = try persistence.load() {
            let decoded = try BackupService.decodeWithMigration(payload, forBackup: false,
                                                                now: now(), calendar: calendar)
            if decoded.didMigrate {
                try persistence.save(BackupService.encode(decoded.state, forBackup: false))
            }
            state = decoded.state
        } else {
            let initialState = AppSnapshot()
            let initialPayload = try BackupService.encode(initialState, forBackup: false)
            try persistence.save(initialPayload)
            state = initialState
        }
        refreshExternalSurfaces()
    }

    @discardableResult
    func update(_ edit: (inout AppSnapshot) throws -> Void) -> Bool {
        do {
            var candidate = state
            try edit(&candidate)
            let payload = try BackupService.encode(candidate, forBackup: false)
            try persistence.save(payload)
            state = candidate
            refreshExternalSurfaces()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // Publish only after a durable commit, on launch, or on activation. A
    // projection failure must not roll back authoritative, successfully saved work.
    func refreshExternalSurfaces() {
        do { try publisher.publish(state, now: now()) }
        catch {
            errorMessage = "Your data is saved, but an external display could not be updated: \(error.localizedDescription)"
        }
        activityGeneration &+= 1
        let generation = activityGeneration
        let previous = activityTask
        activityTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.activityGeneration == generation else { return }
            await self.liveActivities.synchronize(with: self.state)
        }
    }

    func projectName(_ id: UUID) -> String { state.projects.first { $0.id == id }?.name ?? "Project" }

    func saveProject(_ project: Project) -> Bool {
        update { state in
            if let index = state.projects.firstIndex(where: { $0.id == project.id }) {
                if state.activeTimer?.projectID == project.id && state.projects[index].status != project.status {
                    throw AppError.invalid("End this project's timer before changing its status.")
                }
                var updated = project
                // Editing a default deliberately replaces the previous session preference.
                updated.lastFocusMinutes = project.focusMinutes == state.projects[index].focusMinutes
                    ? state.projects[index].lastFocusMinutes : nil
                state.projects[index] = updated
            } else { state.projects.append(project) }
        }
    }

    @discardableResult
    func rememberFocusDuration(projectID: UUID, minutes: Int) -> Bool {
        update { state in
            guard let index = state.projects.firstIndex(where: { $0.id == projectID }) else {
                throw AppError.invalid("This project is no longer available.")
            }
            state.projects[index].lastFocusMinutes = minutes
        }
    }

    @discardableResult
    func startFocus(projectID: UUID, minutes: Int) -> Bool {
        if update({ try TimerEngine.startFocus(&$0, projectID: projectID, minutes: minutes, now: now()) }) {
            scheduleNotification()
            return true
        }
        return false
    }

    func startBreak() {
        if update({ try TimerEngine.startBreak(&$0, now: now()) }) { scheduleNotification() }
    }

    func endTimer() {
        guard let active = state.activeTimer else { return }
        if update({ TimerEngine.finish(&$0, now: now(), force: true) }) { cancelNotification(timerID: active.id) }
    }

    func reconcile() {
        let date = now()
        guard let active = state.activeTimer, date >= active.deadline else { return }
        if update({ TimerEngine.finish(&$0, now: date) }) {
            cancelNotification(timerID: active.id)
            if state.settings.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }

    func discardFocus(timerID: UUID) {
        guard state.activeTimer?.id == timerID, state.activeTimer?.kind == .focus else { return }
        if update({ TimerEngine.discardFocus(&$0, timerID: timerID) }) {
            cancelNotification(timerID: timerID)
        }
    }

    @discardableResult
    func deleteSession(_ sessionID: UUID) -> Bool {
        update { TimerEngine.deleteSession(&$0, sessionID: sessionID) }
    }

    func restore(_ backup: AppSnapshot) -> Bool {
        guard state.activeTimer == nil else { errorMessage = "End the timer before restoring a backup."; return false }
        guard backup.activeTimer == nil else { errorMessage = "A backup cannot contain an active timer."; return false }
        if update({ $0 = backup }) {
            notificationCenter.removeAllPendingNotificationRequests()
            return true
        }
        return false
    }

    private func cancelNotification(timerID: UUID) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["timer.\(timerID.uuidString)"])
    }

    func scheduleNotification() {
        guard !ProcessInfo.processInfo.arguments.contains("--disable-notifications") else { return }
        guard let timer = state.activeTimer else { return }
        let sound = state.settings.notificationSound
        let name = projectName(timer.projectID)
        Task {
            do {
                let center = notificationCenter
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted, state.activeTimer?.id == timer.id else { return }
                let remaining = timer.deadline.timeIntervalSince(now())
                guard remaining > 0 else { reconcile(); return }
                let content = UNMutableNotificationContent()
                content.title = "\(timer.kind.title) complete"
                content.body = timer.kind == .focus ? "Your focus on \(name) is saved. Your break is ready." : "Ready for your next focus session?"
                if sound { content.sound = .default }
                let identifier = "timer.\(timer.id.uuidString)"
                let request = UNNotificationRequest(identifier: identifier, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false))
                try await center.add(request)
                if state.activeTimer?.id != timer.id { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
            } catch { errorMessage = "The timer is running, but its notification could not be scheduled: \(error.localizedDescription)" }
        }
    }
}
