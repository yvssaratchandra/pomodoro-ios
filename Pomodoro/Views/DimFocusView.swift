import SwiftUI

struct DimFocusView: View {
    let timer: ActiveTimer
    let reveal: () -> Void
    let capture: () -> Void

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()
                Button(action: reveal) {
                    Color.black.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reveal Focus")
                .accessibilityIdentifier("dimFocusReveal")

                HStack(spacing: 16) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = context.date.timeIntervalSince(timer.startedAt)
                        let progress = min(1, max(0, elapsed / Double(max(1, timer.plannedSeconds))))
                        GeometryReader { track in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.indigo.opacity(0.12))
                                Capsule().fill(Color.indigo.opacity(0.65))
                                    .frame(width: track.size.width * progress)
                            }
                        }
                        .frame(height: 3)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Focus progress")
                        .accessibilityValue("\(max(0, Int(timer.deadline.timeIntervalSince(context.date)))) seconds remaining")
                    }
                    Button(action: capture) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.indigo.opacity(0.65))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Capture thought")
                    .accessibilityIdentifier("dimFocusCapture")
                }
                .padding(.horizontal, 32)
            }
        }
        .background(.black)
        .statusBarHidden()
        .accessibilityIdentifier("dimFocusSurface")
    }
}
