import Foundation
import SwiftUI

enum BrowserUtilityText: Sendable {
    case localized(LocalizedStringResource)
    case verbatim(String)

    var view: Text {
        switch self {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let value):
            Text(value)
        }
    }

    func resolvedForSearch(
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch self {
        case .localized(var resource):
            resource.locale = locale
            return String(localized: resource)
        case .verbatim(let value):
            return value
        }
    }
}
