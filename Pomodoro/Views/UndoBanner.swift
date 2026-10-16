import SwiftUI

struct UndoBanner: View {
    @Bindable var store: AppStore
    var body: some View {
        if let pending = store.pendingSessionDeletion {
            HStack {
                Text(pending.sessions.count == 1 ? "Session deleted" : "\(pending.sessions.count) sessions deleted")
                    .font(.subheadline)
                Spacer()
                Button("Undo") { store.undoSessionDeletion() }.accessibilityIdentifier("session.undo")
                Button("Dismiss", systemImage: "xmark") { store.dismissSessionUndo() }.labelStyle(.iconOnly)
            }
            .padding().background(.regularMaterial)
        }
    }
}
