import SwiftUI

struct BrowserOnboardingFailureMessage: View {
    let message: BrowserOnboardingFailureText

    var body: some View {
        switch message {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let text):
            Text(verbatim: text)
        }
    }
}
