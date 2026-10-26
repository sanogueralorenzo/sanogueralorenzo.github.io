import SwiftUI

struct BrowserPlatformAddressInputModifier: ViewModifier {
    // MARK: - Static Variables

    /// A combined search/address field must retain the ordinary space bar.
    /// URL keyboards remove it and make multi-word searches needlessly hard.
    static let keyboardType = UIKeyboardType.default

    // MARK: - Actions - Rendering

    func body(content: Content) -> some View {
        content
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(Self.keyboardType)
            .submitLabel(.go)
    }
}
