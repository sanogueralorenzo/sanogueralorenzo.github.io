import SwiftUI

struct BrowserImportFailureMessage: View {
    let message: BrowserImportFailureText

    var body: some View {
        switch message {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let text):
            Text(verbatim: text)
        }
    }
}
