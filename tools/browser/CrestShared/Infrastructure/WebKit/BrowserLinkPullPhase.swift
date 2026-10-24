import WebKit

/// Where a link pull a page reports stands. Each phase hands its message to
/// the receiver's method for it, or to none: the receiver follows the
/// pointer itself once a pull begins.
struct BrowserLinkPullPhase: Hashable, Sendable {
    // MARK: - Static Variables

    static let ready = BrowserLinkPullPhase(name: "ready") { message, frame, receiver in
        receiver.ready(message, from: frame)
    }
    static let retire = BrowserLinkPullPhase(name: "retire") { message, _, receiver in receiver.retire(message) }
    static let begin = BrowserLinkPullPhase(name: "begin") { message, _, receiver in receiver.begin(message) }
    static let move = BrowserLinkPullPhase(name: "move") { _, _, _ in }
    static let end = BrowserLinkPullPhase(name: "end") { _, _, _ in }
    static let cancel = BrowserLinkPullPhase(name: "cancel") { _, _, _ in }
    static let all = [ready, retire, begin, move, end, cancel]

    // MARK: - Types

    typealias Deliver = @MainActor @Sendable (BrowserLinkPullMessage, WKFrameInfo, any BrowserLinkPullReceiver) -> Void

    // MARK: - Variables

    /// The bridge's spelling.
    let name: String
    private let deliver: Deliver

    // MARK: - Initializers

    private init(name: String, deliver: @escaping Deliver) {
        self.name = name
        self.deliver = deliver
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String) -> BrowserLinkPullPhase? {
        all.first { $0.name == name }
    }

    // MARK: - Actions - Delivery

    /// Hands `message`, which `frame` sent, to `receiver`.
    @MainActor func apply(
        _ message: BrowserLinkPullMessage, from frame: WKFrameInfo, to receiver: any BrowserLinkPullReceiver
    ) {
        deliver(message, frame, receiver)
    }

    // MARK: - Equatable

    static func == (lhs: BrowserLinkPullPhase, rhs: BrowserLinkPullPhase) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
