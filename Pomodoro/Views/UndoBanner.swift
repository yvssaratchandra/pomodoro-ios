import SwiftUI

struct UndoBanner: View {
    @Bindable var store: AppStore
    var body: some View {
        if let pending = store.pendingDeletion {
            HStack {
                Text(pending.message)
                    .font(.subheadline)
                Spacer()
                Button("Undo") { store.undoDeletion() }.accessibilityIdentifier("session.undo")
                Button("Dismiss", systemImage: "xmark") { store.dismissUndo() }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
            .padding().background(.regularMaterial)
        }
    }
}
