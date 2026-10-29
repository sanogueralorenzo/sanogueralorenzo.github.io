import Foundation

struct BrowserBlockedPopupNotice: Equatable, Sendable {
    let origin: SiteOrigin
    let status: BlockedPopupStatus
}

/// One indication per page document, coalesced before announcing it.
struct BrowserBlockedPopupPageState: Equatable, Sendable {
    private(set) var notice: BrowserBlockedPopupNotice?
    private(set) var documentIdentifier: String?
    private(set) var indicationRevision = 0

    init() {}

    init(notice: BrowserBlockedPopupNotice?, documentIdentifier: String?, indicationRevision: Int) {
        self.notice = notice
        self.documentIdentifier = documentIdentifier
        self.indicationRevision = indicationRevision
    }

    @discardableResult
    mutating func recordBlockedAttempt(documentIdentifier: String, origin: SiteOrigin) -> Bool {
        guard valid, origin.isValid, !documentIdentifier.isEmpty, documentIdentifier.utf16.count <= 128,
            notice == nil
        else { return false }
        notice = BrowserBlockedPopupNotice(origin: origin, status: .blocked)
        self.documentIdentifier = documentIdentifier
        indicationRevision = Int(Int32(truncatingIfNeeded: indicationRevision) &+ 1)
        return true
    }

    @discardableResult
    mutating func recordPermissionAllowed() -> Bool { change(from: .blocked, to: .allowedAwaitingRetry) }

    @discardableResult
    mutating func recordPermissionBlockedAgain() -> Bool { change(from: .allowedAwaitingRetry, to: .blocked) }

    @discardableResult
    mutating func clearForNavigation() -> Bool {
        guard valid, notice != nil || documentIdentifier.nonEmpty != nil else { return false }
        notice = nil
        documentIdentifier = nil
        return true
    }

    @discardableResult
    mutating func clearAfterAllowedPopup() -> Bool {
        guard valid, notice?.status == .allowedAwaitingRetry else { return false }
        notice = nil
        documentIdentifier = nil
        return true
    }

    private var valid: Bool {
        notice?.origin.isValid != false && (documentIdentifier?.utf16.count ?? 0) <= 128
    }

    private mutating func change(from: BlockedPopupStatus, to: BlockedPopupStatus) -> Bool {
        guard valid, let notice, notice.status == from else { return false }
        self.notice = BrowserBlockedPopupNotice(origin: notice.origin, status: to)
        documentIdentifier = documentIdentifier.nonEmpty
        return true
    }
}
