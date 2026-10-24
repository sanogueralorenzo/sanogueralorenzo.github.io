import SwiftUI

extension BrowserSpaceAccessFailure {
    var message: LocalizedStringResource {
        switch self {
        case .authenticationDenied:
            "Authentication failed. Try again."
        case .authenticationUnavailable:
            "Authentication didn’t complete. Try again."
        }
    }
}
