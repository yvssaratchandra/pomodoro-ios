import SwiftUI
import SwiftData
import UserNotifications
import Observation

struct PendingDeletion {
    var sessions: [FocusSession]
    var thoughts: [CapturedThought] = []
    var count: Int { sessions.count + thoughts.count }
    var message: String {
        if thoughts.isEmpty { return sessions.count == 1 ? "Session deleted" : "\(sessions.count) sessions deleted" }
        if sessions.isEmpty { return thoughts.count == 1 ? "Thought deleted" : "\(thoughts.count) thoughts deleted" }
        return "\(count) items deleted"
    }
    var expiresAt: TimeInterval
}

@MainActor @Observable final class AppStore {
    private(set) var state: AppSnapshot
    private(set) var widgetUpdateError: String?
    var errorMessage: String?
    private(set) var lastFinishedSessionID: UUID?
    private(set) var pendingDeletion: PendingDeletion?
    private let uptime: () -> TimeInterval
    private let voiceOver: () -> Bool
    private let persistence: any SnapshotPersistence
    private let now: () -> Date
    private let publisher: any SnapshotPublishing
    private let liveActivities: any LiveActivityManaging
    private let notificationCenter: any TimerNotificationCenter
    private let notifications: NotificationService
    @ObservationIgnored private var activityTask: Task<Void, Never>?
    @ObservationIgnored private var activityGeneration: UInt64 = 0

    convenience init(container: ModelContainer) throws {
        try self.init(persistence: SwiftDataSnapshotPersistence(container: container))
    }

    init(persistence: any SnapshotPersistence,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         voiceOver: (() -> Bool)? = nil,
         publisher: (any SnapshotPublishing)? = nil,
         liveActivities: (any LiveActivityManaging)? = nil,
         notificationCenter: (any TimerNotificationCenter)? = nil) throws {
        self.persistence = persistence
        self.uptime = uptime
        self.voiceOver = voiceOver ?? { UIAccessibility.isVoiceOverRunning }
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
        let center = notificationCenter ?? SystemTimerNotificationCenter()
        self.notificationCenter = center
        self.notifications = NotificationService(center: center, now: now)
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
            if !Set(state.projects.map(\.id)).isSubset(of: Set(candidate.projects.map(\.id))) {
                pendingDeletion = nil
            }
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
        do {
            try publisher.publish(state, now: now())
            widgetUpdateError = nil
        } catch {
            widgetUpdateError = error.localizedDescription
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

    func saveProject(_ project: Project, focusDuration: Int? = nil) -> Bool {
        update { state in
            if let index = state.projects.firstIndex(where: { $0.id == project.id }) {
                if state.activeTimer?.projectID == project.id && state.projects[index].status != project.status {
                    throw AppError.invalid("End this project's timer before changing its status.")
                }
                var updated = project
                // Editing a default deliberately replaces the previous session preference.
                updated.lastFocusMinutes = project.focusMinutes == state.projects[index].focusMinutes
                    ? state.projects[index].lastFocusMinutes : nil
                if let focusDuration {
                    updated.focusMinutes = focusDuration
                    updated.lastFocusMinutes = nil
                }
                state.projects[index] = updated
            } else {
                var added = project
                if let focusDuration { added.focusMinutes = focusDuration; added.lastFocusMinutes = nil }
                state.projects.append(added)
            }
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
    func startFocus(projectID: UUID, minutes: Int, intention: String? = nil) -> Bool {
        if update({ try TimerEngine.startFocus(&$0, projectID: projectID, minutes: minutes, intention: intention, now: now()) }) {
            lastFinishedSessionID = nil
            scheduleNotification()
            return true
        }
        return false
    }

    func editIntention(id: UUID, active: Bool, text: String) -> Bool {
        update { state in
            let intention = try SessionText.normalize(text)
            if active {
                guard state.activeTimer?.id == id else { throw AppError.invalid("This timer has already ended.") }
                state.activeTimer?.intention = intention
            } else {
                guard let index = state.sessions.firstIndex(where: { $0.id == id }) else { throw AppError.invalid("This session is no longer available.") }
                state.sessions[index].intention = intention
            }
        }
    }

    func saveDailyGoals(_ minutes: [Int]) -> Bool {
        update { try GoalEngine.setDaily(&$0.goalPlan, minutes: minutes, now: now()) }
    }

    func captureThought(context: ThoughtCaptureContext, text: String) -> Bool {
        createThought(context: context, text: text) != nil
    }
    func createThought(context: ThoughtCaptureContext, text: String) -> UUID? {
        var createdID: UUID?
        let saved = update {
            createdID = try ThoughtEngine.capture(&$0, context: context, text: text, now: now())
        }
        return saved ? createdID : nil
    }
    func editThought(id: UUID, text: String) -> Bool { update { try ThoughtEngine.edit(&$0, id: id, text: text) } }
    func setThoughtCompleted(id: UUID, completed: Bool) -> Bool {
        update { try ThoughtEngine.setCompleted(&$0, id: id, completed: completed, now: now()) }
    }
    @discardableResult func deleteThought(id: UUID) -> Bool {
        deleteThoughts(ids: [id])
    }

    @discardableResult func deleteThoughts(ids: Set<UUID>) -> Bool {
        expireUndo()
        let removed = state.thoughts.filter { ids.contains($0.id) }
        guard !removed.isEmpty, removed.count == ids.count else { return false }
        guard update({ $0.thoughts.removeAll { ids.contains($0.id) } }) else { return false }
        var pending = pendingDeletion ?? PendingDeletion(sessions: [], expiresAt: 0)
        pending.thoughts.append(contentsOf: removed)
        pending.expiresAt = uptime() + (voiceOver() ? 30 : 10)
        pendingDeletion = pending
        return true
    }

    @discardableResult func setThoughtsCompleted(ids: Set<UUID>, completed: Bool) -> Bool {
        guard !ids.isEmpty else { return false }
        return update { state in
            for id in ids { try ThoughtEngine.setCompleted(&state, id: id, completed: completed, now: now()) }
        }
    }

    func saveWeeklyGoal(projectID: UUID, minutes: Int?, effectiveWeek: Date? = nil) -> Bool {
        update { state in
            guard state.projects.contains(where: { $0.id == projectID }) else { throw AppError.invalid("Project unavailable.") }
            try GoalEngine.setWeekly(&state.goalPlan, projectID: projectID, minutes: minutes, now: now(), effectiveWeek: effectiveWeek)
        }
    }

    func cancelScheduledWeeklyGoal(projectID: UUID, effectiveWeek: Date) -> Bool {
        update { state in
            let c = GoalEngine.calendar()
            let monday = GoalEngine.week(containing: effectiveWeek, calendar: c).start
            guard monday > GoalEngine.week(containing: now(), calendar: c).start else {
                throw AppError.invalid("Only future targets can be cancelled.")
            }
            let day = LocalDay(monday, calendar: c)
            state.goalPlan.weeklyProjectRevisions.removeAll { $0.projectID == projectID && $0.effectiveFrom == day }
        }
    }

    func canDeleteProject(id: UUID) -> Bool {
        let pending = pendingDeletion.flatMap { uptime() < $0.expiresAt ? $0 : nil }
        return state.projects.contains(where: { $0.id == id && $0.breadcrumb == nil })
            && !state.sessions.contains(where: { $0.projectID == id })
            && !state.thoughts.contains(where: { $0.projectID == id })
            && state.activeTimer?.projectID != id && state.breakOffer?.projectID != id
            && !(pending?.sessions.contains(where: { $0.projectID == id }) ?? false)
            && !(pending?.thoughts.contains(where: { $0.projectID == id }) ?? false)
    }

    @discardableResult func deleteEmptyProject(id: UUID) -> Bool {
        guard canDeleteProject(id: id) else {
            errorMessage = "This project still has content. Put it on hold or merge it with another project."
            return false
        }
        expireUndo()
        let pending = pendingDeletion
        let saved = update { state in
            state.projects.removeAll { $0.id == id }
            state.goalPlan.weeklyProjectRevisions.removeAll { $0.projectID == id }
        }
        if saved { pendingDeletion = pending }
        return saved
    }

    func startBreak() {
        if update({ try TimerEngine.startBreak(&$0, now: now()) }) { scheduleNotification() }
    }

    func endTimer() {
        guard let active = state.activeTimer else { return }
        if update({ TimerEngine.finish(&$0, now: now(), force: true) }) {
            if active.kind == .focus { lastFinishedSessionID = active.id }
            cancelNotification(timerID: active.id)
        }
    }

    func reconcile() {
        let date = now()
        guard let active = state.activeTimer, date >= active.deadline else { return }
        if update({ TimerEngine.finish(&$0, now: date) }) {
            if active.kind == .focus { lastFinishedSessionID = active.id }
            notifications.naturalCompletion(timerID: active.id)
            if state.settings.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }

    func saveNextStep(sessionID: UUID, text: String, promote: Bool) -> Bool {
        update { state in
            guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }),
                  let projectIndex = state.projects.firstIndex(where: { $0.id == state.sessions[index].projectID }) else {
                throw AppError.invalid("This session is no longer available.")
            }
            let note = try SessionText.normalize(text)
            state.sessions[index].nextStep = note
            if promote { state.projects[projectIndex].breadcrumb = note.map { ProjectBreadcrumb(text: $0, updatedAt: now(), originSessionID: sessionID) } }
        }
    }

    func editProjectBreadcrumb(projectID: UUID, text: String) -> Bool {
        update { state in
            guard let index = state.projects.firstIndex(where: { $0.id == projectID }) else { throw AppError.invalid("Project unavailable.") }
            let origin = state.projects[index].breadcrumb?.originSessionID
            state.projects[index].breadcrumb = try SessionText.normalize(text).map { ProjectBreadcrumb(text: $0, updatedAt: now(), originSessionID: origin) }
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
        expireUndo()
        guard let session = state.sessions.first(where: { $0.id == sessionID }) else { return false }
        guard update({ TimerEngine.deleteSession(&$0, sessionID: sessionID) }) else { return false }
        var pending = pendingDeletion ?? PendingDeletion(sessions: [], expiresAt: 0)
        pending.sessions.append(session)
        pending.expiresAt = uptime() + (voiceOver() ? 30 : 10)
        pendingDeletion = pending
        return true
    }

    func expireUndo() {
        if let pendingDeletion, uptime() >= pendingDeletion.expiresAt { self.pendingDeletion = nil }
    }

    func dismissUndo() { pendingDeletion = nil }

    @discardableResult func undoDeletion() -> Bool {
        expireUndo()
        guard let pending = pendingDeletion else { return false }
        let success = update { state in
            let existing = Set(state.sessions.map(\.id))
            let projects = Set(state.projects.map(\.id))
            let thoughtIDs = Set(state.thoughts.map(\.id))
            guard pending.sessions.allSatisfy({ !existing.contains($0.id) && projects.contains($0.projectID) }),
                  pending.thoughts.allSatisfy({ !thoughtIDs.contains($0.id) && ($0.projectID == nil || projects.contains($0.projectID!)) }) else {
                throw AppError.invalid("These items cannot be restored because their project or history has changed.")
            }
            state.sessions.append(contentsOf: pending.sessions)
            state.thoughts.append(contentsOf: pending.thoughts)
        }
        if success { pendingDeletion = nil }
        return success
    }

    func restore(_ backup: AppSnapshot) -> Bool {
        guard state.activeTimer == nil else { errorMessage = "End the timer before restoring a backup."; return false }
        guard backup.activeTimer == nil else { errorMessage = "A backup cannot contain an active timer."; return false }
        if update({ $0 = backup }) {
            pendingDeletion = nil
            lastFinishedSessionID = nil
            notifications.reset()
            return true
        }
        return false
    }

    private func cancelNotification(timerID: UUID) { notifications.cancel(timerID: timerID) }

    func scheduleNotification(reportAuthorizationFailure: Bool = false) {
        guard !ProcessInfo.processInfo.arguments.contains("--disable-notifications"), let timer = state.activeTimer else { return }
        notifications.schedule(timer: timer, project: projectName(timer.projectID),
            isCurrent: { [weak self] in self?.state.activeTimer?.id == timer.id },
            expired: { [weak self] in self?.reconcile() },
            failed: { [weak self] in self?.errorMessage = $0 },
            reportAuthorizationFailure: reportAuthorizationFailure)
    }

    func testCompletionAlert(kind: TimerKind) async -> String {
        do { return try await notifications.test(sound: state.settings.completionSound(for: kind)) }
        catch { return "Unable to schedule test alert: \(error.localizedDescription)" }
    }

    @discardableResult
    func updateCompletionAudio(enabled: Bool? = nil, kind: TimerKind? = nil, sound: CompletionSound? = nil) -> Bool {
        reconcile()
        if let timer = state.activeTimer, timer.deadline <= now() { return false }
        guard sound == nil || kind != nil else { return false }
        let oldTimer = state.activeTimer
        guard update({ state in
            if let enabled { state.settings.notificationSound = enabled }
            if let sound, let kind {
                if kind == .focus { state.settings.focusCompletionSound = sound }
                else { state.settings.breakCompletionSound = sound }
            }
            if let timer = state.activeTimer {
                state.activeTimer?.completionSound = state.settings.completionSound(for: timer.kind)
            }
        }) else { return false }
        if let timer = state.activeTimer, timer.completionSound != oldTimer?.completionSound {
            scheduleNotification(reportAuthorizationFailure: timer.completionSound != .silent)
        }
        return true
    }
}
