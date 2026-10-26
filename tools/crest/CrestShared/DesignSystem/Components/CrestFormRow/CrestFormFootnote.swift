import SwiftUI

/// The shared explanatory-copy treatment used beneath form controls.
struct CrestFormFootnote: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text).crestFormFootnote()
    }
}

#if DEBUG
    #Preview("Component") {
        CrestFormFootnote("Changes apply to all Spaces.").padding().frame(width: 340)
    }
#endif
