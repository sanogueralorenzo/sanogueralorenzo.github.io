import SwiftUI

struct BrowserPictureInPictureToggle: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        Toggle(
            "Picture in Picture when switching tabs",
            isOn: $preferences.automaticallyEntersPictureInPicture
        )
        .accessibilityIdentifier("automatic-picture-in-picture-toggle")
    }
}
