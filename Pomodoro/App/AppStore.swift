import SwiftUI
import SwiftData
import UserNotifications
import Observation

// A single versioned document makes a timer transition or restore one atomic database save.
@Model final class AppDocument {
    var payload: Data
    init(payload: Data) { self.payload = payload }
}

@MainActor @Observable final class AppStore {
    private(set) var state: AppSnapshot
    var errorMessage: String?
    private let context: ModelContext
    private let document: AppDocument

    init(container: ModelContainer) throws {
        context = ModelContext(container)
        context.autosaveEnabled = false
        let documents = try context.fetch(FetchDescriptor<AppDocument>())
        if let existing = documents.first {
            document = existing
            state = try BackupService.decode(existing.payload, forBackup: false)
        } else {
            let initialState = AppSnapshot()
            let initialPayload = try BackupService.encode(initialState, forBackup: false)
            state = initialState
            document = AppDocument(payload: initialPayload)
            context.insert(document)
            try context.save()
        }
    }

    @discardableResult
    func update(_ edit: (inout AppSnapshot) throws -> Void) -> Bool {
        do {
            var candidate = state
            try edit(&candidate)
            let payload = try BackupService.encode(candidate, forBackup: false)
            let previous = document.payload
            document.payload = payload
            do { try context.save() }
            catch {
                context.rollback()
                document.payload = previous
                throw error
            }
            state = candidate
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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

    func startFocus(projectID: UUID, minutes: Int) {
        if update({ try TimerEngine.startFocus(&$0, projectID: projectID, minutes: minutes, now: Date()) }) {
            scheduleNotification()
        }
    }

    func startBreak() {
        if update({ try TimerEngine.startBreak(&$0, now: Date()) }) { scheduleNotification() }
    }

    func endTimer() {
        guard let active = state.activeTimer else { return }
        if update({ TimerEngine.finish(&$0, now: Date(), force: true) }) { cancelNotification(timerID: active.id) }
    }

    func reconcile() {
        guard let active = state.activeTimer, Date() >= active.deadline else { return }
        if update({ TimerEngine.finish(&$0, now: Date()) }) {
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
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return true
        }
        return false
    }

    private func cancelNotification(timerID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timer.\(timerID.uuidString)"])
    }

    func scheduleNotification() {
        guard !ProcessInfo.processInfo.arguments.contains("--disable-notifications") else { return }
        guard let timer = state.activeTimer else { return }
        let sound = state.settings.notificationSound
        let name = projectName(timer.projectID)
        Task {
            do {
                let center = UNUserNotificationCenter.current()
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted, state.activeTimer?.id == timer.id else { return }
                let remaining = timer.deadline.timeIntervalSinceNow
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
