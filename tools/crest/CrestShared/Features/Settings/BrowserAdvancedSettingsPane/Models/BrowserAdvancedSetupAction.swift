import SwiftUI

/// One setup capability supplied by a platform shell to Advanced Settings.
struct BrowserAdvancedSetupAction: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let symbol: String
    var help: LocalizedStringKey?
    var identifier: String?
    let action: () -> Void

    init(
        id: String,
        title: LocalizedStringKey,
        symbol: String,
        help: LocalizedStringKey? = nil,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.help = help
        self.identifier = identifier
        self.action = action
    }
}
