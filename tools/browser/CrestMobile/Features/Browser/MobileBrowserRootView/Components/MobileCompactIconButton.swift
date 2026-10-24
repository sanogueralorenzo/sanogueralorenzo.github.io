import SwiftUI

struct MobileCompactIconButton: View {
    let title: String
    let systemImage: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(
                    width: CrestLayout.minimumHitTarget,
                    height: CrestLayout.minimumHitTarget
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            enabled
                ? Color.primary
                : Color.secondary.opacity(CrestOpacity.controlDisabledForeground)
        )
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

#if DEBUG
    #Preview("Enabled and disabled") {
        HStack {
            MobileCompactIconButton(title: "New Tab", systemImage: "plus", action: {})
            MobileCompactIconButton(title: "Back", systemImage: "chevron.left", enabled: false, action: {})
        }.padding()
    }
#endif
