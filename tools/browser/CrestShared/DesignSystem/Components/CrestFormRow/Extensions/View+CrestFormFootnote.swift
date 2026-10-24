import SwiftUI

extension View {
    /// Applies the explanatory-copy role to content assembled by the caller.
    func crestFormFootnote() -> some View {
        font(.footnote)
            .foregroundStyle(CrestColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
