import Foundation

enum SnapshotMigration {
    private struct Envelope: Decodable {
        let schemaVersion: Int
    }

    // The clock/calendar become relevant when dated goal revisions are added.
    // Keep them explicit so startup and imports share a deterministic context.
    static func upgrade(data: Data, now: Date, calendar: Calendar) throws -> Data {
        guard data.count <= 50_000_000 else {
            throw AppError.invalid("The backup exceeds the 50 MB limit.")
        }
        let version = try JSONDecoder().decode(Envelope.self, from: data).schemaVersion
        guard (1...AppSnapshot.currentSchemaVersion).contains(version) else {
            throw AppError.invalid("This data version is not supported.")
        }
        if version == AppSnapshot.currentSchemaVersion { return data }

        guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.invalid("Invalid stored data.")
        }
        var current = version
        while current < AppSnapshot.currentSchemaVersion {
            switch current {
            case 1:
                guard var settings = document["settings"] as? [String: Any] else {
                    throw AppError.invalid("Invalid timer settings.")
                }
                settings["showProjectNameOnLockScreen"] = false
                settings["showIntentionOnLockScreen"] = false
                document["settings"] = settings
                // Optional intentions decode to nil when absent. Do not add
                // defaults for required legacy fields or reconstruct history.
                current = 2
                document["schemaVersion"] = current
            case 2:
                guard var settings = document["settings"] as? [String: Any],
                      let enabled = settings["notificationSound"] as? Bool else {
                    throw AppError.invalid("Invalid notification settings.")
                }
                settings["focusCompletionSound"] = "systemDefault"
                settings["breakCompletionSound"] = "systemDefault"
                document["settings"] = settings
                if var timer = document["activeTimer"] as? [String: Any] {
                    timer["completionSound"] = enabled ? "systemDefault" : "silent"
                    document["activeTimer"] = timer
                }
                current = 3
                document["schemaVersion"] = current
            case 3:
                guard let settings = document["settings"] as? [String: Any], let minutes = settings["dailyGoalMinutes"] as? Int else {
                    throw AppError.invalid("Invalid daily goal.")
                }
                let day = LocalDay(now, calendar: GoalEngine.calendar(calendar))
                document["goalPlan"] = ["dailyRevisions": [["effectiveFrom": ["year": day.year, "month": day.month, "day": day.day], "minutes": Array(repeating: minutes, count: 7)]], "weeklyProjectRevisions": []]
                current = 4
                document["schemaVersion"] = current
            case 4:
                current = 5
                document["schemaVersion"] = current
            case 5:
                document["thoughts"] = []
                current = 6
                document["schemaVersion"] = current
            case 6:
                guard var settings = document["settings"] as? [String: Any] else { throw AppError.invalid("Invalid settings.") }
                settings["consistencyTargetDays"] = 4
                document["settings"] = settings
                current = 7
                document["schemaVersion"] = current
            default:
                throw AppError.invalid("This data version is not supported.")
            }
        }
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }
}
