import SwiftUI

enum BrowserPlatformSearchEnginePresentation {
    static let pickerStyle = BrowserSpaceBrowsingPickerPresentationStyle.paddedMenu
    static let editorStyle = BrowserSearchEngineEditorPresentationStyle.navigation
    static let keyboardDismissalDelay: Duration? = .milliseconds(350)
}

struct BrowserPlatformSearchEngineSheetSizingModifier: ViewModifier {
    let size: BrowserSearchEngineSheetSize

    func body(content: Content) -> some View {
        content.presentationDetents([.medium, .large])
    }
}
