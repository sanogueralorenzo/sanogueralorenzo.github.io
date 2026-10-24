import Foundation

struct BrowserCredentialFillRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let origin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    let usernameHint: String?
    let passwordKind: CredentialPasswordKind
    let isCrossOriginFrame: Bool
    let requestedAt: Date

    /// Where the field that asked sits in the page's viewport, in CSS pixels,
    /// or `nil` where nothing can be said about it.
    ///
    /// Only a main-frame field ever fills this in. A subframe reports its rect
    /// in its own viewport, and a cross-origin one cannot know where that
    /// viewport lands in the page — so a prompt raised from a frame keeps the
    /// placement it has always had rather than pointing at the wrong place.
    let fieldRect: BrowserCredentialFieldRect?

    init(
        id: UUID,
        origin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        usernameHint: String?,
        passwordKind: CredentialPasswordKind,
        isCrossOriginFrame: Bool,
        requestedAt: Date,
        fieldRect: BrowserCredentialFieldRect? = nil
    ) {
        self.id = id
        self.origin = origin
        self.topLevelOrigin = topLevelOrigin
        self.usernameHint = usernameHint
        self.passwordKind = passwordKind
        self.isCrossOriginFrame = isCrossOriginFrame
        self.requestedAt = requestedAt
        self.fieldRect = fieldRect
    }

    /// The same request, following its field to where the page just moved it.
    ///
    /// Everything the prompt is identified and guarded by — its ID above all —
    /// is carried through unchanged, so a scroll moves the panel without
    /// re-asking the vault or re-arming any of the fill guards.
    func following(_ fieldRect: BrowserCredentialFieldRect) -> Self {
        BrowserCredentialFillRequest(
            id: id,
            origin: origin,
            topLevelOrigin: topLevelOrigin,
            usernameHint: usernameHint,
            passwordKind: passwordKind,
            isCrossOriginFrame: isCrossOriginFrame,
            requestedAt: requestedAt,
            fieldRect: fieldRect
        )
    }
}
