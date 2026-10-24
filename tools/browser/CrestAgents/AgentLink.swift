import Foundation

// What the agent helper and the Crest it ships inside say to each other over
// the agent socket, one JSON object per line. The helper speaks the Model
// Context Protocol with the agent; only tool calls cross to Crest.

// MARK: - Types

/// The agent as it named itself to the helper.
struct AgentClientInfo: Codable, Equatable, Sendable {
    let name: String
    let title: String?
    let version: String?
}

/// What a tool answered, as the protocol carries it to the agent: what the
/// model reads, the same as data when the tool has any, and whether it is an
/// error the model should see.
struct AgentToolResult: Codable, Equatable, Sendable {
    /// One part of what a tool answered: text, or an image.
    struct Content: Codable, Equatable, Sendable {
        /// What a part is, as the protocol spells it.
        enum Kind: String, Codable, Sendable {
            case text
            case image
        }

        let type: Kind
        let text: String?
        let data: String?
        let mimeType: String?

        static func text(_ text: String) -> Self {
            Self(type: .text, text: text, data: nil, mimeType: nil)
        }

        static func png(_ data: Data) -> Self {
            Self(type: .image, text: nil, data: data.base64EncodedString(), mimeType: "image/png")
        }
    }

    let content: [Content]
    let isError: Bool

    /// A refusal the model reads and may act on.
    static func error(_ message: String) -> Self {
        Self(content: [.text(message)], isError: true)
    }
}

/// What the helper says to Crest.
enum AgentLinkRequest: Codable, Sendable {
    /// The helper connected for the agent `client`, speaking link `version`.
    case attach(version: Int, client: AgentClientInfo?)
    /// The agent called tool `name` with `arguments`, as call `id`.
    case call(id: Int, name: String, arguments: AgentJSON)
}

/// What Crest says to the helper.
enum AgentLinkResponse: Codable, Sendable {
    /// Crest heard the agent; its tools are `tools`, as the protocol lists
    /// them, which an older helper lists from then on.
    case attached(tools: AgentJSON)
    /// Crest will not talk to this helper, for `reason`.
    case refused(reason: AgentLinkRefusal)
    /// Call `id` answered `result`.
    case result(id: Int, result: AgentToolResult)
}

/// Why Crest refuses a helper.
enum AgentLinkRefusal: String, Codable, Sendable {
    /// The helper is from a build of Crest whose link differs from the one
    /// running, such as the build an update replaced; the agent starts it
    /// again to reach this Crest.
    case staleHelper
    /// The person has agents turned off.
    case agentsOff
}

extension AgentLinkRequest {
    /// The link's revision; a helper and a Crest of different revisions never
    /// talk.
    static let version = 1
    /// The longest line a helper sends Crest. A call past it fails in the
    /// helper, so it never ends the agent's connection.
    static let maximumBytes = 4 << 20
}

extension AgentLinkResponse {
    /// The longest line Crest sends a helper, well within what the helper
    /// reads. An answer past it fails that call.
    static let maximumBytes = 6 << 20
}
