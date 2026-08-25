import SwiftUI

/// The row of duration buttons. Holds no state — every action is sent outward.
struct DurationBar: View {
    let customMinutes: Int
    let isActive: Bool
    var onSelect: (Int) -> Void
    var onIndefinite: () -> Void
    var onStop: () -> Void

    private static let quickDurations = [15, 30, 60]

    /// Two rows rather than one: cramming five buttons into a single row
    /// truncates the duration labels in the narrow panel, and the label is the
    /// only information a button carries.
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Self.quickDurations, id: \.self) { minutes in
                    durationButton(minutes)
                }
                durationButton(customMinutes)
            }

            HStack(spacing: 6) {
                Button {
                    onIndefinite()
                } label: {
                    Label("Indefinite", systemImage: "infinity")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(Text("Turn on indefinitely"))

                Button {
                    onStop()
                } label: {
                    // "Stop" only needs room for itself; the slack all goes to
                    // the longer label on the left, which would otherwise be
                    // cut down to "Indefini…".
                    Label("Stop", systemImage: "stop.fill")
                        .frame(minWidth: 56)
                }
                .disabled(!isActive)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func durationButton(_ minutes: Int) -> some View {
        Button { onSelect(minutes) } label: {
            Text(label(for: minutes))
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text("Turn on for \(Plural.minutes(minutes))"))
    }

    /// Whole hours read as hours to keep it short; anything else is minutes.
    /// The label has to fit on one line in a 288pt panel, so there is no room
    /// for "60 minutes".
    private func label(for minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m"
    }
}
