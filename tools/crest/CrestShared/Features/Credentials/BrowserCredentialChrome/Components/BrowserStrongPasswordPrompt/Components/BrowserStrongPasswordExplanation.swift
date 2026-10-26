import SwiftUI

/// What the offer actually does, and where the password ends up.
struct BrowserStrongPasswordExplanation: View {
    let spaceName: String

    var body: some View {
        Text(
            "Crest saves a unique 20-character password in \(spaceName) first, then fills it here and in the confirmation field."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserStrongPasswordExplanation(spaceName: "Work").padding().frame(width: 360)
    }
#endif
