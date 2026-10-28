import SwiftUI

struct BrowserSpaceSettingsGlassButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(CrestOpacity.disabled))
                .frame(width: CrestLayout.minimumHitTarget, height: CrestLayout.minimumHitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSpaceSettingsGlassButton(title: "Customize", symbol: "paintpalette", action: {}).padding()
    }
#endif
