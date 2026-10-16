import Foundation

enum BackupService {
    static let currentSchemaVersion = AppSnapshot.currentSchemaVersion

    static func encode(_ state: AppSnapshot, forBackup: Bool = true) throws -> Data {
        if forBackup && state.activeTimer != nil { throw AppError.invalid("End the timer before exporting a backup.") }
        try validate(state)
        let encoder = JSONEncoder()
        // Foundation reference-date seconds preserve subsecond elapsed work exactly.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    static func decode(_ data: Data, forBackup: Bool = true,
                       now: Date = Date(), calendar: Calendar = .current) throws -> AppSnapshot {
        try decodeWithMigration(data, forBackup: forBackup, now: now, calendar: calendar).state
    }

    static func decodeWithMigration(_ data: Data, forBackup: Bool = true,
                                    now: Date = Date(), calendar: Calendar = .current) throws
        -> (state: AppSnapshot, didMigrate: Bool) {
        let upgraded = try SnapshotMigration.upgrade(data: data, now: now, calendar: calendar)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let state = try decoder.decode(AppSnapshot.self, from: upgraded)
        try validate(state)
        if forBackup && state.activeTimer != nil { throw AppError.invalid("Backups cannot contain a running timer.") }
        return (state, upgraded != data)
    }

    static func validate(_ state: AppSnapshot) throws {
        guard state.schemaVersion == currentSchemaVersion else { throw AppError.invalid("This data version is not supported.") }
        let settings = state.settings
        guard (1...7).contains(settings.consistencyTargetDays) else { throw AppError.invalid("Choose 1 to 7 focused days per week.") }
        guard (1...1440).contains(settings.dailyGoalMinutes),
              (10...60).contains(settings.defaultFocusMinutes),
              (1...60).contains(settings.defaultShortBreakMinutes),
              (1...60).contains(settings.defaultLongBreakMinutes),
              (1...12).contains(settings.longBreakInterval),
              (0...11).contains(state.completedInCycle) else { throw AppError.invalid("Invalid timer settings.") }
        let projectIDs = Set(state.projects.map(\.id))
        guard Set(state.thoughts.map(\.id)).count == state.thoughts.count else { throw AppError.invalid("Duplicate thought identifiers.") }
        for thought in state.thoughts {
            guard thought.projectID == nil || projectIDs.contains(thought.projectID!), try SessionText.normalize(thought.text, limit: 500) != nil,
                  thought.createdAt.timeIntervalSince1970.isFinite,
                  thought.completedAt == nil || (thought.completedAt!.timeIntervalSince1970.isFinite && thought.completedAt! >= thought.createdAt) else {
                throw AppError.invalid("Invalid captured thought.")
            }
        }
        try GoalEngine.validate(state.goalPlan, projectIDs: projectIDs)
        guard projectIDs.count == state.projects.count,
              Set(state.sessions.map(\.id)).count == state.sessions.count else {
            throw AppError.invalid("Duplicate identifiers in data.")
        }
        for project in state.projects {
            if let note = project.breadcrumb {
                guard try SessionText.normalize(note.text) != nil, note.updatedAt.timeIntervalSince1970.isFinite else {
                    throw AppError.invalid("Invalid project next-step note.")
                }
            }
            if let minutes = project.lastFocusMinutes, !(10...60).contains(minutes) {
                throw AppError.invalid("Invalid remembered focus duration.")
            }
            guard !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  project.name.count <= 100, project.createdAt.timeIntervalSince1970.isFinite,
                  (10...60).contains(project.focusMinutes),
                  (1...60).contains(project.shortBreakMinutes),
                  (1...60).contains(project.longBreakMinutes) else { throw AppError.invalid("Invalid project details.") }
        }
        for session in state.sessions {
            _ = try SessionText.normalize(session.nextStep)
            try validateIntention(session.intention)
            guard projectIDs.contains(session.projectID),
                  session.startedAt.timeIntervalSince1970.isFinite, session.endedAt.timeIntervalSince1970.isFinite,
                  (600...3600).contains(session.plannedSeconds), session.plannedSeconds % 60 == 0,
                  session.endedAt >= session.startedAt, session.duration <= Double(session.plannedSeconds),
                  session.outcome != .completed || session.duration == Double(session.plannedSeconds) else {
                throw AppError.invalid("Invalid focus session.")
            }
        }
        if let timer = state.activeTimer {
            try validateIntention(timer.intention)
            let range = timer.kind == .focus ? 600...3600 : 60...3600
            guard projectIDs.contains(timer.projectID), range.contains(timer.plannedSeconds),
                  timer.plannedSeconds % 60 == 0, timer.startedAt.timeIntervalSince1970.isFinite,
                  (1...12).contains(timer.longBreakInterval),
                  !state.sessions.contains(where: { $0.id == timer.id }), state.breakOffer == nil else {
                throw AppError.invalid("Invalid active timer.")
            }
            if timer.kind == .focus {
                guard (1...60).contains(timer.shortBreakMinutes), (1...60).contains(timer.longBreakMinutes),
                      state.projects.first(where: { $0.id == timer.projectID })?.status == .ongoing else {
                    throw AppError.invalid("Invalid active focus session.")
                }
            }
        }
        if let offer = state.breakOffer {
            guard projectIDs.contains(offer.projectID), offer.kind != .focus, (1...60).contains(offer.minutes) else {
                throw AppError.invalid("Invalid pending break.")
            }
        }
    }

    private static func validateIntention(_ text: String?) throws {
        if let text, text.count > 280 {
            throw AppError.invalid("Session intentions must be 280 characters or fewer.")
        }
    }
}
