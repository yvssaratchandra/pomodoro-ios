import Foundation
import SwiftData

// Preserve the existing model and single atomic, versioned JSON document.
@Model final class AppDocument {
    var payload: Data
    init(payload: Data) { self.payload = payload }
}

@MainActor final class SwiftDataSnapshotPersistence: SnapshotPersistence {
    private let context: ModelContext
    private var document: AppDocument?
    private let saveContext: @MainActor (ModelContext) throws -> Void

    init(container: ModelContainer,
         saveContext: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }) throws {
        context = ModelContext(container)
        context.autosaveEnabled = false
        document = try context.fetch(FetchDescriptor<AppDocument>()).first
        self.saveContext = saveContext
    }

    func load() throws -> Data? { document?.payload }

    func save(_ payload: Data) throws {
        if let document {
            let previous = document.payload
            document.payload = payload
            do { try saveContext(context) }
            catch {
                context.rollback()
                document.payload = previous
                throw error
            }
        } else {
            let initial = AppDocument(payload: payload)
            context.insert(initial)
            do {
                try saveContext(context)
                document = initial
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}
