import SwiftUI

/// A credential prompt's failure line.
struct BrowserCredentialPromptError: View {
    let message: Text

    init(_ message: LocalizedStringKey) {
        self.message = Text(message)
    }

    init(verbatim message: String) {
        self.message = Text(verbatim: message)
    }

    var body: some View {
        message
            .font(.caption)
            .foregroundStyle(.red)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCredentialPromptError("The password could not be saved. Try again.").padding().frame(width: 360)
    }
#endif
