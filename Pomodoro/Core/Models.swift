import Foundation

enum ProjectStatus: String, Codable, CaseIterable, Identifiable {
    case ongoing, suspended, completed
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct Project: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var status: ProjectStatus = .ongoing
    var focusMinutes = 25
    var lastFocusMinutes: Int?
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var createdAt = Date()

    var preferredFocusMinutes: Int { lastFocusMinutes ?? focusMinutes }
}

enum SessionOutcome: String, Codable { case completed, interrupted }
enum TimerKind: String, Codable {
    case focus, shortBreak, longBreak
    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
}

struct FocusSession: Identifiable, Codable, Equatable {
    var id: UUID
    var projectID: UUID
    var startedAt: Date
    var endedAt: Date
    var plannedSeconds: Int
    var outcome: SessionOutcome
    var intention: String?
    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

struct ActiveTimer: Identifiable, Codable, Equatable {
    var id = UUID()
    var projectID: UUID
    var kind: TimerKind
    var startedAt: Date
    var plannedSeconds: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var longBreakInterval: Int
    var intention: String?
    var completionSound: CompletionSound = .systemDefault
    var deadline: Date { startedAt.addingTimeInterval(Double(plannedSeconds)) }
    func elapsed(at date: Date) -> TimeInterval {
        min(Double(plannedSeconds), max(0, date.timeIntervalSince(startedAt)))
    }
}

struct BreakOffer: Codable, Equatable {
    var projectID: UUID
    var kind: TimerKind
    var minutes: Int
}

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

struct Settings: Codable, Equatable {
    var dailyGoalMinutes = 240
    var defaultFocusMinutes = 25
    var defaultShortBreakMinutes = 5
    var defaultLongBreakMinutes = 15
    var longBreakInterval = 4
    var notificationSound = true
    var focusCompletionSound: CompletionSound = .systemDefault
    var breakCompletionSound: CompletionSound = .systemDefault
    var haptics = true
    var appearance: Appearance = .system
    var showProjectNameOnLockScreen = false
    var showIntentionOnLockScreen = false
}

struct AppSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 3
    var schemaVersion = AppSnapshot.currentSchemaVersion
    var projects: [Project] = []
    var sessions: [FocusSession] = []
    var settings = Settings()
    var activeTimer: ActiveTimer?
    var breakOffer: BreakOffer?
    var completedInCycle = 0
}

enum AppError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum DurationText {
    static func work(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds))
        if seconds < 60 { return "\(seconds) sec" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
