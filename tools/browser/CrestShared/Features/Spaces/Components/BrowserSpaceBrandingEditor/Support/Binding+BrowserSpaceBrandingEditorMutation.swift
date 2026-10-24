import SwiftUI

extension Binding where Value == SpaceBranding {
    func editorUpdate(
        _ mutation: (inout SpaceBranding) -> Void
    ) {
        var updated = wrappedValue
        mutation(&updated)
        wrappedValue = updated.normalized()
    }
}
