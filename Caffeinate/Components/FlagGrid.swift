import SwiftUI
import CaffeinateKit

/// Four status dots. Filled means that assertion is genuinely held.
///
/// Flags that are off are shown too, not just the ones that are on: the user
/// needs the full picture to know what is NOT being held, rather than inferring
/// it from a shortened list.
struct FlagGrid: View {
    let effectiveFlags: AssertionFlags

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(AssertionFlags.all, id: \.rawValue) { flag in
                indicator(for: flag)
            }
        }
    }

    private func indicator(for flag: AssertionFlags) -> some View {
        let isOn = effectiveFlags.contains(flag)
        return Label {
            Text(flag.displayName)
                .foregroundStyle(isOn ? .primary : .secondary)
        } icon: {
            Image(systemName: isOn ? "circle.fill" : "circle")
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .imageScale(.small)
        }
        .font(.callout)
        .animation(.easeInOut(duration: 0.15), value: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(flag.displayName))
        .accessibilityValue(isOn ? Text("held") : Text("not held"))
    }
}
