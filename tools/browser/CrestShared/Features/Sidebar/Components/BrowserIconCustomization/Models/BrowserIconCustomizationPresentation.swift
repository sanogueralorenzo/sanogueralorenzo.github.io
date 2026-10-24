import SwiftUI

struct BrowserIconCustomizationPresentation {
    let isPresented: Binding<Bool>
    let title: LocalizedStringKey
    let currentEmoji: String?
    var currentSystemSymbol: String? = nil
    var showsReset = false
    var resetTitle: LocalizedStringKey? = nil
    let setEmoji: (String) -> Void
    var setSystemSymbol: ((String) -> Void)? = nil
    var reset: (() -> Void)? = nil
}
