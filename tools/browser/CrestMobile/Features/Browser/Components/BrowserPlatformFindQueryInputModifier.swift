import SwiftUI

/// Mobile keeps the find field literal — nothing capitalized, nothing
/// corrected — and labels its return key for search.
struct BrowserPlatformFindQueryInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
    }
}
