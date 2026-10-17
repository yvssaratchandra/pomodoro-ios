import Foundation

struct WidgetStorageDiagnostics {
    let configuredGroup: String?
    let declaredGroups: [String]
    let selectedGroup: String?
    let failure: String?
    let directory: URL?
}

enum SharedWidgetContainer {
    private static let signingCache = SignedGroupCache()

    static func diagnostics() -> WidgetStorageDiagnostics {
        resolve(configured: Bundle.main.object(forInfoDictionaryKey: "PomodoroAppGroup") as? String,
                signing: signingCache.read(), container: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) })
    }

    static func resolve(configured: String?, signing: Result<SignedAppGroups, Error>,
                        container: (String) -> URL?) -> WidgetStorageDiagnostics {
        var declared: [String] = []
        var selected: String?
        do {
            let permissions = try signing.get()
            declared = permissions.groups
            let group = try permissions.group(for: configured ?? "")
            selected = group
            guard let directory = container(group) else {
                throw AppGroupAccessError()
            }
            return WidgetStorageDiagnostics(configuredGroup: configured, declaredGroups: declared,
                                            selectedGroup: selected, failure: nil, directory: directory)
        } catch {
            return WidgetStorageDiagnostics(configuredGroup: configured, declaredGroups: declared,
                                            selectedGroup: selected, failure: error.localizedDescription, directory: nil)
        }
    }

    static func directory() -> URL? { diagnostics().directory }

    static func read() -> WidgetSnapshot? {
        directory().flatMap { WidgetSnapshotFile.read(in: $0) }
    }
}

private struct AppGroupAccessError: LocalizedError {
    var errorDescription: String? { "iOS did not grant access to the signed widget group." }
}

private final class SignedGroupCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: SignedAppGroups?

    func read() -> Result<SignedAppGroups, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return .success(cached) }
        return Result {
            guard let executable = Bundle.main.executableURL else { throw SigningReadError.missingSignature }
            let permissions = try SignedAppGroups.read(from: Data(contentsOf: executable, options: .mappedIfSafe))
            cached = permissions
            return permissions
        }
    }
}
