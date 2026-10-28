import SwiftUI

/// The add control at the end of a chip rail.
struct CrestSpaceChipAddAction {
    let title: LocalizedStringKey
    var accessibilityIdentifier: String?
    let perform: () -> Void

    init(
        title: LocalizedStringKey,
        accessibilityIdentifier: String? = nil,
        perform: @escaping () -> Void
    ) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.perform = perform
    }
}
