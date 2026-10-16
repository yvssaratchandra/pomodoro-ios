import Foundation
import UserNotifications

@MainActor final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center: any TimerNotificationCenter
    private let now: () -> Date
    private var generation = 0
    private var testGeneration = 0
    private var activeID: UUID?
    private var scheduled: Set<UUID> = []
    private var completed: Set<UUID> = []
    private var delivered: Set<UUID> = []

    init(center: any TimerNotificationCenter, now: @escaping () -> Date) {
        self.center = center
        self.now = now
        super.init()
        if center is SystemTimerNotificationCenter { UNUserNotificationCenter.current().delegate = self }
    }

    static func sound(_ selection: CompletionSound) -> UNNotificationSound? {
        if selection == .silent { return nil }
        if let filename = selection.filename { return UNNotificationSound(named: UNNotificationSoundName(rawValue: filename)) }
        return .default
    }

    func schedule(timer: ActiveTimer, project: String, isCurrent: @escaping () -> Bool,
                  expired: @escaping () -> Void, failed: @escaping (String) -> Void) {
        guard timer.deadline > now() else { expired(); return }
        generation += 1
        let requestGeneration = generation
        activeID = timer.id
        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted, requestGeneration == generation, isCurrent() else { return }
                let remaining = timer.deadline.timeIntervalSince(now())
                guard remaining > 0 else { expired(); return }
                let content = UNMutableNotificationContent()
                content.title = "\(timer.kind.title) complete"
                content.body = timer.kind == .focus ? "Your focus on \(project) is saved. Your break is ready." : "Ready for your next focus session?"
                content.sound = Self.sound(timer.completionSound)
                content.userInfo = ["timerID": timer.id.uuidString]
                let id = "timer.\(timer.id.uuidString)"
                scheduled.insert(timer.id)
                try await center.add(UNNotificationRequest(identifier: id, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)))
                if !isCurrent(), !completed.contains(timer.id) { center.removePendingNotificationRequests(withIdentifiers: [id]) }
            } catch { failed("The timer is running, but its notification could not be scheduled: \(error.localizedDescription)") }
        }
    }

    func cancel(timerID: UUID) {
        generation += 1
        scheduled.remove(timerID)
        completed.remove(timerID)
        if activeID == timerID { activeID = nil }
        center.removePendingNotificationRequests(withIdentifiers: ["timer.\(timerID.uuidString)"])
    }

    func naturalCompletion(timerID: UUID) {
        if scheduled.contains(timerID) { completed.insert(timerID) }
        if activeID == timerID { activeID = nil }
    }

    func test(sound: CompletionSound) async throws -> String {
        testGeneration += 1
        let current = testGeneration
        center.removePendingNotificationRequests(withIdentifiers: ["completion-sound-test"])
        guard sound != .silent else { return "Sound is off." }
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard current == testGeneration else { return "A newer test was selected." }
        guard granted else { return "Allow notifications in Notification Settings to test an alert." }
        guard await center.soundIsEnabled() else { return "Notification sounds are disabled. Enable them in Notification Settings." }
        guard current == testGeneration else { return "A newer test was selected." }
        let content = UNMutableNotificationContent()
        content.title = "Pomodoro test alert"
        content.body = "Completion sounds use your iPhone's alert volume."
        content.sound = Self.sound(sound)
        content.userInfo = ["soundTest": true]
        try await center.add(UNNotificationRequest(identifier: "completion-sound-test", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        if current != testGeneration { center.removePendingNotificationRequests(withIdentifiers: ["completion-sound-test"]) }
        return "Test alert scheduled. Silent mode, Focus, and notification settings still apply."
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let test = notification.request.content.userInfo["soundTest"] as? Bool == true
        let id = (notification.request.content.userInfo["timerID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            if test { completionHandler(.sound); return }
            guard let id, (id == activeID || completed.contains(id)), !delivered.contains(id) else {
                completionHandler([]); return
            }
            delivered.insert(id)
            completionHandler(.sound)
        }
    }
}
