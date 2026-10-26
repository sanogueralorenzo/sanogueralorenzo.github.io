import SwiftUI

enum BrowserPlatformSearchEnginePresentation {
    static let pickerStyle = BrowserSpaceBrowsingPickerPresentationStyle.paddedMenu
    static let editorStyle = BrowserSearchEngineEditorPresentationStyle.navigation
    static let keyboardDismissalDelay: Duration? = .milliseconds(350)
}
