import SwiftUI

struct BreakDurationSheet: View {
    let store: AppStore
    let offer: BreakOffer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: Int
    @State private var saveError: String?

    init(store: AppStore, offer: BreakOffer) {
        self.store = store
        self.offer = offer
        _draft = State(initialValue: offer.minutes)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(store.projectName(offer.projectID)).font(.headline)
                Picker("Break duration", selection: $draft) {
                    ForEach(1...60, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.wheel)
                .accessibilityIdentifier("break.duration.wheel")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appScreen()
            .navigationTitle("Break duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("break.duration.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if store.setBreakDuration(offer: offer, minutes: draft) { dismiss() }
                        else {
                            saveError = store.errorMessage
                            store.errorMessage = nil
                        }
                    }
                    .accessibilityIdentifier("break.duration.done")
                }
            }
            .alert("Unable to save duration", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
