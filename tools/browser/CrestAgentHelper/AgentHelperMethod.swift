import Foundation

/// A Model Context Protocol method the endpoint hears, as the protocol spells
/// it, with how the endpoint answers it as a request and takes it as a
/// notification. A method the endpoint does not know is one too: it answers
/// that there is no such method and takes no notification.
struct AgentHelperMethod: Sendable {
    // MARK: - Static Variables

    static let initialize = Self(name: "initialize") { endpoint, params, id, _ in
        endpoint.initialize(params, id: id)
    }
    static let discover = Self(name: "server/discover") { endpoint, _, id, _ in
        endpoint.send(result: endpoint.discovery, id: id, modern: true)
    }
    static let ping = Self(name: "ping") { endpoint, _, id, modern in
        endpoint.send(result: .object([:]), id: id, modern: modern)
    }
    static let listTools = Self(name: "tools/list") { endpoint, _, id, modern in
        endpoint.send(
            result: .object(["tools": endpoint.announcedTools ?? AgentToolDefinition.catalog]), id: id, modern: modern)
    }
    static let callTool = Self(name: "tools/call") { endpoint, params, id, modern in
        endpoint.call(params, id: id, modern: modern)
    }
    static let initialized = Self(name: "notifications/initialized")
    /// The agent gave up on a call it made.
    static let cancelled = Self(name: "notifications/cancelled") { endpoint, params in
        endpoint.cancel(params)
    }

    static let all: [AgentHelperMethod] = [initialize, discover, ping, listTools, callTool, initialized, cancelled]

    // MARK: - Variables

    let name: String
    private let answering: @Sendable (isolated AgentHelperEndpoint, AgentJSON, AgentJSON, Bool) -> Void
    private let noticing: @Sendable (isolated AgentHelperEndpoint, AgentJSON) -> Void

    // MARK: - Initializers

    /// A method the endpoint takes only as a notification, or not at all.
    private init(
        name: String, notice: @escaping @Sendable (isolated AgentHelperEndpoint, AgentJSON) -> Void = { _, _ in }
    ) {
        self.name = name
        answering = { endpoint, _, id, _ in endpoint.send(error: .methodNotFound(name), id: id) }
        noticing = notice
    }

    /// A method the endpoint answers as a request.
    private init(
        name: String, answer: @escaping @Sendable (isolated AgentHelperEndpoint, AgentJSON, AgentJSON, Bool) -> Void
    ) {
        self.name = name
        answering = answer
        noticing = { _, _ in }
    }

    // MARK: - Actions - Messages

    /// The method the protocol spells `name`.
    static func named(_ name: String) -> Self {
        all.first { $0.name == name } ?? Self(name: name)
    }

    /// Answers the request `id` with `params`, for a client that speaks the
    /// modern protocol when `modern` is true.
    func answer(_ params: AgentJSON, id: AgentJSON, modern: Bool, on endpoint: isolated AgentHelperEndpoint) {
        answering(endpoint, params, id, modern)
    }

    /// Takes the notification with `params`.
    func notice(_ params: AgentJSON, on endpoint: isolated AgentHelperEndpoint) {
        noticing(endpoint, params)
    }
}
