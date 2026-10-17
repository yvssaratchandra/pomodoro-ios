import Foundation

enum TimerEngine {
    static func startFocus(_ state: inout AppSnapshot, projectID: UUID, minutes: Int, intention: String? = nil, now: Date) throws {
        guard state.activeTimer == nil else { throw AppError.invalid("End the current timer first.") }
        guard (10...60).contains(minutes),
              let project = state.projects.first(where: { $0.id == projectID }), project.status == .ongoing else {
            throw AppError.invalid("Choose an ongoing project and a focus duration from 10 to 60 minutes.")
        }
        let normalizedIntention = try SessionText.normalize(intention)
        state.breakOffer = nil
        state.activeTimer = ActiveTimer(projectID: projectID, kind: .focus, startedAt: now,
            plannedSeconds: minutes * 60, shortBreakMinutes: project.shortBreakMinutes,
            longBreakMinutes: project.longBreakMinutes, longBreakInterval: state.settings.longBreakInterval,
            intention: normalizedIntention, completionSound: state.settings.completionSound(for: .focus))
    }

    static func setBreakDuration(_ state: inout AppSnapshot, offer: BreakOffer, minutes: Int) throws {
        guard state.activeTimer == nil, state.breakOffer == offer, offer.kind != .focus,
              (1...60).contains(minutes),
              let index = state.projects.firstIndex(where: { $0.id == offer.projectID }) else {
            throw AppError.invalid("This break is no longer available to change.")
        }
        state.breakOffer?.minutes = minutes
        if offer.kind == .longBreak { state.projects[index].longBreakMinutes = minutes }
        else { state.projects[index].shortBreakMinutes = minutes }
    }

    static func startBreak(_ state: inout AppSnapshot, now: Date) throws {
        guard state.activeTimer == nil, let offer = state.breakOffer else {
            throw AppError.invalid("No break is ready to start.")
        }
        state.activeTimer = ActiveTimer(projectID: offer.projectID, kind: offer.kind, startedAt: now,
            plannedSeconds: offer.minutes * 60, shortBreakMinutes: 0, longBreakMinutes: 0,
            longBreakInterval: state.settings.longBreakInterval, completionSound: state.settings.completionSound(for: offer.kind))
        state.breakOffer = nil
    }

    @discardableResult
    static func finish(_ state: inout AppSnapshot, now: Date, force: Bool = false) -> Bool {
        guard let timer = state.activeTimer, force || now >= timer.deadline else { return false }
        state.activeTimer = nil
        guard timer.kind == .focus else { return true }
        let completed = now >= timer.deadline
        let end = min(timer.deadline, max(timer.startedAt, now))
        if !state.sessions.contains(where: { $0.id == timer.id }) {
            state.sessions.append(FocusSession(id: timer.id, projectID: timer.projectID,
                startedAt: timer.startedAt, endedAt: end, plannedSeconds: timer.plannedSeconds,
                outcome: completed ? .completed : .interrupted, intention: timer.intention))
        }
        if completed {
            state.completedInCycle += 1
            let isLong = state.completedInCycle >= timer.longBreakInterval
            if isLong { state.completedInCycle = 0 }
            state.breakOffer = BreakOffer(projectID: timer.projectID, kind: isLong ? .longBreak : .shortBreak,
                minutes: isLong ? timer.longBreakMinutes : timer.shortBreakMinutes)
        }
        return true
    }

    @discardableResult
    static func discardFocus(_ state: inout AppSnapshot, timerID: UUID) -> Bool {
        guard let timer = state.activeTimer, timer.id == timerID, timer.kind == .focus else { return false }
        state.activeTimer = nil
        return true
    }

    // History edits affect statistics; they do not rewind the running break cycle.
    static func deleteSession(_ state: inout AppSnapshot, sessionID: UUID) {
        state.sessions.removeAll { $0.id == sessionID }
    }

    static func merge(_ state: inout AppSnapshot, source: UUID, destination: UUID) throws {
        guard source != destination,
              state.projects.contains(where: { $0.id == source }),
              state.projects.contains(where: { $0.id == destination }) else {
            throw AppError.invalid("Select a different existing destination project.")
        }
        guard state.activeTimer?.projectID != source, state.activeTimer?.projectID != destination else {
            throw AppError.invalid("End the affected project's timer before merging.")
        }
        for index in state.sessions.indices where state.sessions[index].projectID == source {
            state.sessions[index].projectID = destination
        }
        for index in state.thoughts.indices where state.thoughts[index].projectID == source { state.thoughts[index].projectID = destination }
        if state.breakOffer?.projectID == source { state.breakOffer?.projectID = destination }
        state.projects.removeAll { $0.id == source }
        state.goalPlan.weeklyProjectRevisions.removeAll { $0.projectID == source }
    }
}
