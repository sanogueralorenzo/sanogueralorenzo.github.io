import Foundation

struct BrowserLinkHoverState {
    static let appearanceDelay = 1.0
    static let expansionDelay = 0.8

    private(set) var destination: BrowserLinkHoverDestination?
    private(set) var isExpanded = false
    private(set) var ticket = 0
    private var document: String?
    private var sequence = 0
    private var candidate: BrowserLinkHoverDestination?
    private var appearanceDeadline = 0.0

    @discardableResult
    mutating func receive(document: String, sequence: Int, href: String?, at now: TimeInterval) -> Int {
        invalidate()
        self.document = document
        self.sequence = sequence
        candidate = href.flatMap(BrowserLinkHoverDestination.init(resolvedURL:))
        appearanceDeadline = now + Self.appearanceDelay
        return ticket
    }

    mutating func leave(document: String, sequence: Int) {
        guard self.document == document, sequence >= self.sequence else { return }
        invalidate()
    }

    @discardableResult
    mutating func reveal(ticket: Int, at now: TimeInterval) -> Bool {
        guard ticket == self.ticket, now >= appearanceDeadline, let candidate else { return false }
        destination = candidate
        return true
    }

    @discardableResult
    mutating func expand(ticket: Int, at now: TimeInterval) -> Bool {
        guard ticket == self.ticket, destination != nil,
            now >= appearanceDeadline + Self.expansionDelay
        else { return false }
        isExpanded = true
        return true
    }

    mutating func invalidate() {
        ticket &+= 1
        candidate = nil
        destination = nil
        document = nil
        sequence = 0
        isExpanded = false
    }
}
