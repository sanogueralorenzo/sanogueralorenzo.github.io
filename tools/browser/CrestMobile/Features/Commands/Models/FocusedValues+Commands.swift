import SwiftUI

extension FocusedValues {
    var mobileBrowserCommandContext: MobileBrowserCommandContext? {
        get { self[MobileBrowserCommandContextFocusedValueKey.self] }
        set { self[MobileBrowserCommandContextFocusedValueKey.self] = newValue }
    }
}
