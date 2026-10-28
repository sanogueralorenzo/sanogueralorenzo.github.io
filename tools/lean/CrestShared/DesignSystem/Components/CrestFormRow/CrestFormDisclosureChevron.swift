import SwiftUI

/// Direction-aware disclosure indicator for a row that navigates or presents.
struct CrestFormDisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(CrestTypography.metadata.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Component") {
        CrestFormDisclosureChevron().padding()
    }
#endif
