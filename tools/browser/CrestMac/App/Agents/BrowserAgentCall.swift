import Foundation

/// One tool call an agent made: the service that answers it, the agent's
/// connection and core session, and the arguments it passed, which each tool
/// reads as its own typed values.
@MainActor
struct BrowserAgentCall {
    // MARK: - Variables

    unowned let agents: BrowserMacAgents
    let link: BrowserMacAgents.Link
    let sessionID: UUID
    let arguments: AgentJSON

    // MARK: - Actions - Arguments

    /// The arguments as `Arguments`, or the failure that names what is wrong.
    func arguments<Arguments: Decodable>(_: Arguments.Type) throws(BrowserAgentFailure) -> Arguments {
        do {
            return try arguments.decoded(as: Arguments.self)
        } catch let error as DecodingError {
            throw .invalidArguments(Self.explanation(of: error))
        } catch {
            throw .invalidArguments(error.localizedDescription)
        }
    }

    private static func explanation(of error: DecodingError) -> String {
        func name(_ path: [any CodingKey]) -> String { path.map(\.stringValue).joined(separator: ".") }
        switch error {
        case .keyNotFound(let key, let context): return "\(name(context.codingPath + [key])) is missing."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(name(context.codingPath)) is not valid."
        @unknown default: return "they could not be read."
        }
    }
}

extension AgentToolResult {
    /// `value` as JSON the model reads, after `note` when there is one. The
    /// text is the whole result: clients that find structured content show
    /// the model only that, which would lose the note.
    static func data(_ value: some Encodable, note: String? = nil) -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let text = (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return Self(content: [.text(note.map { "\($0)\n\(text)" } ?? text)], isError: false)
    }

    /// A message the model reads.
    static func message(_ text: String) -> Self {
        Self(content: [.text(text)], isError: false)
    }
}
