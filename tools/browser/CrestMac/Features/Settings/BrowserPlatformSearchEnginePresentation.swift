import SwiftUI

enum BrowserPlatformSearchEnginePresentation {
    static let pickerStyle = BrowserSpaceBrowsingPickerPresentationStyle.nativePicker
    static let editorStyle = BrowserSearchEngineEditorPresentationStyle.sheet

    static let keyboardDismissalDelay: Duration? = nil
}

struct BrowserPlatformSearchEngineSheetSizingModifier: ViewModifier {
    let size: BrowserSearchEngineSheetSize

    func body(content: Content) -> some View {
        content.frame(minWidth: size.minimumWidth, minHeight: size.minimumHeight)
    }
}
