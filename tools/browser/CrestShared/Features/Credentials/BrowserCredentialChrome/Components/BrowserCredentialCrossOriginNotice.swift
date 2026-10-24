import SwiftUI

/// Says out loud that the form the prompt is about belongs to an embedded frame
/// rather than to the site in the address field.
struct BrowserCredentialCrossOriginNotice: View {
    let message: LocalizedStringKey

    var body: some View {
        Label(
            message,
            systemImage: "rectangle.inset.filled.and.person.filled"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCredentialCrossOriginNotice(message: "This sign-in form belongs to a different website.").padding()
            .frame(width: 360)
    }
#endif
