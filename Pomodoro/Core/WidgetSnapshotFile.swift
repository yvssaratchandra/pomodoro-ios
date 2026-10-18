import Foundation

enum WidgetSnapshotFile {
    static let filename = "WidgetSnapshot.json"

    static func write(_ snapshot: WidgetSnapshot, in directory: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        #if os(iOS)
        try data.write(to: directory.appendingPathComponent(filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        #endif
    }

    static func read(in directory: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(filename)),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              [2, WidgetSnapshot.currentFormatVersion].contains(snapshot.formatVersion),
              snapshot.generatedAt.timeIntervalSince1970.isFinite,
              Set(snapshot.projects.map(\.id)).count == snapshot.projects.count,
              snapshot.projects.allSatisfy({ !$0.name.isEmpty && (10...60).contains($0.preferredFocusMinutes) }) else { return nil }
        if let summary = snapshot.savedFocus, !summary.isValid { return nil }
        if let summaries = snapshot.projectDaySummaries {
            let projectIDs = Set(snapshot.projects.map(\.id))
            guard Set(summaries.map(\.projectID)).count == summaries.count,
                  summaries.allSatisfy({ projectIDs.contains($0.projectID) && $0.savedFocus.isValid &&
                      ($0.targetMinutes == nil || (0...1440).contains($0.targetMinutes!)) }) else { return nil }
        }
        if let timer = snapshot.activeTimer {
            guard timer.startedAt.timeIntervalSince1970.isFinite,
                  timer.deadline.timeIntervalSince1970.isFinite,
                  timer.deadline > timer.startedAt else { return nil }
        }
        return snapshot
    }
}
