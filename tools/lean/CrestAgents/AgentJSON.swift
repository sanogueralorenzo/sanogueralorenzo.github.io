import Foundation

/// A JSON value as it crosses to and from an agent: tool arguments, results
/// and schemas, which Crest reads into typed values at its boundary.
enum AgentJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AgentJSON])
    case object([String: AgentJSON])

    // MARK: - Initializers

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AgentJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: AgentJSON].self))
        }
    }

    // MARK: - Actions - Encoding

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    // MARK: - Actions - Reading

    subscript(key: String) -> AgentJSON? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// The value read as `Value`, as a tool reads its arguments.
    func decoded<Value: Decodable>(as _: Value.Type) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(self))
    }

    /// `value` as JSON, as a tool answers it.
    static func encoded(_ value: some Encodable) -> AgentJSON {
        (try? JSONDecoder().decode(AgentJSON.self, from: JSONEncoder().encode(value))) ?? .null
    }
}
