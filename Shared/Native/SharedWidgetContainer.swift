import Foundation

enum SharedWidgetContainer {
    static func directory() -> URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PomodoroAppGroup") as? String,
              group.hasPrefix("group."), !group.contains("$") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static func read() -> WidgetSnapshot? {
        directory().flatMap { WidgetSnapshotFile.read(in: $0) }
    }
}
