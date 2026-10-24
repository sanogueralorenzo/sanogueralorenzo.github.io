import Foundation

// MARK: - Types

/// What a form message carries, as decoded once from the content script,
/// before its event judges whether the message keeps its contract. A field
/// that is present but not valid is told apart from one the message left out.
struct BrowserCredentialFormFields: Sendable {
    let formID: String?
    let username: String?
    let password: String?
    let passwordKind: CredentialPasswordKind?
    let isTrustedUserEvent: Bool
    let hasVisiblePasswordField: Bool?
    let fieldRect: BrowserCredentialFieldRect?
    let containsUsername: Bool
    let containsPassword: Bool
    let containsPasswordKind: Bool

    var hasInvalidUsername: Bool { containsUsername && username == nil }
    var hasInvalidPassword: Bool { containsPassword && password == nil }
    var hasInvalidPasswordKind: Bool { containsPasswordKind && passwordKind == nil }
}

/// A narrowly validated message from Crest's isolated WebKit content world.
/// It deliberately cannot be encoded, and its textual representations never
/// include the password received during a submit event.
struct BrowserCredentialFormMessage: Sendable, Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    // MARK: - Static Variables

    static let contractVersion = 1
    private static let maximumFormIDLength = 256
    private static let maximumUsernameLength = 1_024
    private static let maximumPasswordLength = 16_384

    // MARK: - Variables

    let event: BrowserCredentialFormEvent
    let formID: String?
    let username: String?
    let password: String?
    let passwordKind: CredentialPasswordKind?
    let isTrustedUserEvent: Bool
    let hasVisiblePasswordField: Bool?

    /// Where the focused password field sits in its frame's viewport, where the
    /// page reported it. Optional on a focus: a field the bridge cannot measure
    /// still deserves a prompt, just not an anchored one.
    let fieldRect: BrowserCredentialFieldRect?

    var description: String {
        "BrowserCredentialFormMessage(event: \(event.name), formID: \(formID ?? "none"), username: \(username ?? "none"), password: <redacted>)"
    }

    var debugDescription: String { description }

    private enum CodingKeys: String, CodingKey {
        case version
        case event
        case formID
        case username
        case password
        case passwordKind
        case trusted
        case hasVisiblePasswordField
        case fieldRect
    }

    // MARK: - Initializers

    /// The message a script message's body carries, decoded once; nil for a
    /// body that breaks the contract.
    init?(body: Any) {
        guard JSONSerialization.isValidJSONObject(body),
            let data = try? JSONSerialization.data(withJSONObject: body),
            let message = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return nil
        }
        self = message
    }

    /// Decodes the message and holds it to its event's contract. A field of
    /// the wrong type reads as present but invalid, as an unreadable one.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .version) == Self.contractVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container, debugDescription: "Unsupported form message version.")
        }
        let event = try container.decode(BrowserCredentialFormEvent.self, forKey: .event)
        let fields = BrowserCredentialFormFields(
            formID: Self.nonemptyString(.formID, in: container, maximumLength: Self.maximumFormIDLength),
            username: Self.nonemptyString(.username, in: container, maximumLength: Self.maximumUsernameLength),
            password: Self.nonemptyString(.password, in: container, maximumLength: Self.maximumPasswordLength),
            passwordKind: (try? container.decodeIfPresent(String.self, forKey: .passwordKind))
                .flatMap(Self.passwordKind(named:)),
            isTrustedUserEvent: (try? container.decodeIfPresent(Bool.self, forKey: .trusted)) ?? false,
            hasVisiblePasswordField: try? container.decodeIfPresent(Bool.self, forKey: .hasVisiblePasswordField),
            fieldRect: try? container.decodeIfPresent(BrowserCredentialFieldRect.self, forKey: .fieldRect),
            containsUsername: container.contains(.username),
            containsPassword: container.contains(.password),
            containsPasswordKind: container.contains(.passwordKind))
        guard event.accepts(fields) else {
            throw DecodingError.dataCorruptedError(
                forKey: .event, in: container, debugDescription: "The message breaks its event's contract.")
        }

        self.event = event
        formID = fields.formID
        username = fields.username
        password = fields.password
        passwordKind = fields.passwordKind
        isTrustedUserEvent = fields.isTrustedUserEvent
        hasVisiblePasswordField = fields.hasVisiblePasswordField
        fieldRect = fields.fieldRect
    }

    // MARK: - Actions - Decoding

    /// The content script's spelling of a password field's kind.
    private static func passwordKind(named name: String) -> CredentialPasswordKind? {
        switch name {
        case "current": .current
        case "new": .new
        default: nil
        }
    }

    private static func nonemptyString(
        _ key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>, maximumLength: Int
    ) -> String? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }
}
