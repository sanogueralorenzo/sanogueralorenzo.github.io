import Foundation

/// What a form message from Crest's content script reports. Each event says
/// what shape its message must have, and what it is to the core's capture
/// rules.
struct BrowserCredentialFormEvent: Hashable, Sendable, Decodable {
    // MARK: - Static Variables

    static let username = BrowserCredentialFormEvent(
        name: "username", captureEvent: .username,
        accepts: { fields in
            fields.formID != nil
                && fields.username != nil
                && fields.isTrustedUserEvent
                && !fields.containsPassword
                && !fields.containsPasswordKind
        })
    static let focus = BrowserCredentialFormEvent(
        name: "focus", captureEvent: .focus, closesFillWhenRefused: true,
        accepts: { fields in
            fields.formID != nil
                && fields.isTrustedUserEvent
                && !fields.hasInvalidUsername
                && !fields.containsPassword
                && fields.passwordKind != nil
        })
    static let submit = BrowserCredentialFormEvent(
        name: "submit", captureEvent: .submit,
        accepts: { fields in
            fields.formID != nil
                && fields.isTrustedUserEvent
                && !fields.hasInvalidUsername
                && !fields.hasInvalidPassword
                && !fields.hasInvalidPasswordKind
                && fields.password != nil
                && fields.passwordKind != nil
        })
    static let documentState = BrowserCredentialFormEvent(
        name: "documentState", captureEvent: .documentState, weighsPendingCandidate: true,
        accepts: { fields in
            fields.hasVisiblePasswordField != nil
                && !fields.containsUsername
                && !fields.containsPassword
                && !fields.containsPasswordKind
        })

    /// The focused field moved under the prompt already on show — the page
    /// scrolled, the window resized, or the reader changed the page's zoom.
    /// It carries geometry and nothing else, so it can never open a prompt,
    /// only move one.
    static let fieldGeometry = BrowserCredentialFormEvent(
        name: "fieldGeometry", captureEvent: nil,
        accepts: { fields in
            // Geometry and nothing else. A trusted gesture is not asked for —
            // a scroll is not one — and no credential material is accepted, so
            // the event cannot be a way in for anything but a rect.
            fields.formID != nil
                && fields.fieldRect != nil
                && !fields.containsUsername
                && !fields.containsPassword
                && !fields.containsPasswordKind
        })

    static let all: [BrowserCredentialFormEvent] = [username, focus, submit, documentState, fieldGeometry]

    // MARK: - Variables

    /// The content script's name for the event.
    let name: String

    /// What the event is to the core's capture rules, or nil for an event
    /// that only moves the prompt already on show.
    let captureEvent: CredentialCaptureEvent?

    /// Whether the page closes the fill prompt it shows when the core refuses
    /// the event: a refused focus must not leave a prompt for another field.
    let closesFillWhenRefused: Bool

    /// Whether the core weighs the save candidate waiting from an earlier
    /// submit against this event.
    let weighsPendingCandidate: Bool

    /// Whether a message of this event has the fields it needs and none it
    /// must not carry.
    let accepts: @Sendable (BrowserCredentialFormFields) -> Bool

    // MARK: - Initializers

    private init(
        name: String, captureEvent: CredentialCaptureEvent?, closesFillWhenRefused: Bool = false,
        weighsPendingCandidate: Bool = false, accepts: @escaping @Sendable (BrowserCredentialFormFields) -> Bool
    ) {
        self.name = name
        self.captureEvent = captureEvent
        self.closesFillWhenRefused = closesFillWhenRefused
        self.weighsPendingCandidate = weighsPendingCandidate
        self.accepts = accepts
    }

    /// The event the content script names; an event this build does not know
    /// fails to decode.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let event = Self.all.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown form event \(name)")
        }
        self = event
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCredentialFormEvent, rhs: BrowserCredentialFormEvent) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
