import SwiftUI

extension BrowserLinkPreferenceStore {
    /// A settings switch for `behavior`, whose state `value` reads from the
    /// preferences the core published; turning it sends the change.
    func binding(_ behavior: LinkBehavior, reading value: KeyPath<LinkPreferences, Bool>) -> Binding<Bool> {
        Binding {
            self.preferences[keyPath: value]
        } set: { isOn in
            self.setBehavior(behavior, isOn: isOn)
        }
    }
}
