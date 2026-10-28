import Foundation

enum BrowserBrowsingMode: Equatable, Sendable {
    case standard
    case privateBrowsing

    var isPrivate: Bool { self == .privateBrowsing }
}
