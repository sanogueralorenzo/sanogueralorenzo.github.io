import Foundation

/// The helper's Model Context Protocol endpoint over the agent's standard
/// streams. It speaks both eras: a modern client names its protocol version
/// and itself on every request, and a legacy one opens with `initialize`,
/// which holds for the helper's life. It answers discovery and the tool list
/// itself, so an agent sees Crest's tools even while Crest is closed, and
/// hands each tool call to Crest.
actor AgentHelperEndpoint {
    // MARK: - Types

    /// JSON-RPC and Model Context Protocol errors the endpoint answers.
    struct Failure: Error {
        static let parse = Self(code: -32700, message: "The line is not JSON.")
        static let invalidRequest = Self(code: -32600, message: "The message is not a JSON-RPC 2.0 request.")
        static let invalidParams = Self(code: -32602, message: "The request's parameters are not valid.")

        static func methodNotFound(_ method: String) -> Self {
            Self(code: -32601, message: "Crest has no method \(method).")
        }

        static func unsupportedVersion(_ requested: String) -> Self {
            Self(
                code: -32022, message: "Unsupported protocol version",
                data: .object([
                    "supported": .array(MCPProtocolVersion.all.map { .string($0.name) }),
                    "requested": .string(requested),
                ]))
        }

        let code: Int
        let message: String
        var data: AgentJSON?
    }

    // MARK: - Static Variables

    private static let metaVersion = "io.modelcontextprotocol/protocolVersion"
    private static let metaClient = "io.modelcontextprotocol/clientInfo"
    private static let metaServer = "io.modelcontextprotocol/serverInfo"
    /// How long a modern client may keep the tool list before asking again.
    private static let listLifetime = 60_000.0

    // MARK: - Variables

    private let output: AgentLineChannel
    private let link: AgentAppLink
    private let serverInfo: AgentJSON
    /// The legacy revision `initialize` agreed on, which holds for the
    /// helper's life; nil for a modern client.
    private var legacy: MCPProtocolVersion?
    /// The agent as it last named itself.
    private var client: AgentClientInfo?
    /// The tool calls running, by the agent's request identity.
    private var calls: [String: Task<Void, Never>] = [:]
    /// The tool list the agent last heard of, when it is Crest's rather than
    /// the helper's own.
    private(set) var announcedTools: AgentJSON?

    // MARK: - Initializers

    init(output: AgentLineChannel, link: AgentAppLink, version: String) {
        self.output = output
        self.link = link
        serverInfo = .object(["name": .string("crest-browser"), "title": .string("Crest"), "version": .string(version)])
    }

    // MARK: - Actions - Messages

    /// Answers one message the agent sent.
    func receive(_ line: Data) {
        guard let message = try? JSONDecoder().decode(AgentJSON.self, from: line), case .object = message else {
            send(error: .parse, id: .null)
            return
        }
        let id = message["id"]
        guard let name = message["method"]?.string else {
            // A response to nothing the helper asked, or a malformed message.
            if let id { send(error: .invalidRequest, id: id) }
            return
        }
        let params = message["params"] ?? .object([:])
        let method = AgentHelperMethod.named(name)
        guard let id else {
            method.notice(params, on: self)
            return
        }
        var modern = false
        if let requested = params["_meta"]?[Self.metaVersion]?.string {
            guard let version = MCPProtocolVersion.named(requested), version.isModern else {
                send(error: .unsupportedVersion(requested), id: id)
                return
            }
            modern = true
            if let named = try? params["_meta"]?[Self.metaClient]?.decoded(as: AgentClientInfo.self) { client = named }
        }
        method.answer(params, id: id, modern: modern, on: self)
    }

    // MARK: - Actions - Lifecycle

    func initialize(_ params: AgentJSON, id: AgentJSON) {
        let requested = MCPProtocolVersion.named(params["protocolVersion"]?.string)
        let version = requested.flatMap { $0.isModern ? nil : $0 } ?? MCPProtocolVersion.newestLegacy
        legacy = version
        client = try? params["clientInfo"]?.decoded(as: AgentClientInfo.self)
        send(
            result: .object([
                "protocolVersion": .string(version.name),
                "capabilities": .object(["tools": .object(["listChanged": .bool(true)])]),
                "serverInfo": serverInfo, "instructions": .string(AgentToolDefinition.instructions),
            ]), id: id, modern: false)
    }

    var discovery: AgentJSON {
        .object([
            "supportedVersions": .array(MCPProtocolVersion.all.map { .string($0.name) }),
            "capabilities": .object(["tools": .object([:])]),
            "instructions": .string(AgentToolDefinition.instructions), "ttlMs": .number(Self.listLifetime),
            "cacheScope": .string("private"),
        ])
    }

    // MARK: - Actions - Tools

    func call(_ params: AgentJSON, id: AgentJSON, modern: Bool) {
        guard let name = params["name"]?.string else {
            send(error: .invalidParams, id: id)
            return
        }
        let arguments = params["arguments"] ?? .object([:])
        let client = client
        let key = Self.key(id)
        calls[key] = Task {
            let result: AgentToolResult
            do {
                result = try await link.call(name, arguments: arguments, client: client)
            } catch let failure as AgentAppLink.Failure {
                result = .error(failure.message)
            } catch {
                result = .error("Crest could not run the tool.")
            }
            guard !Task.isCancelled else { return }
            await finish(key, result: result, id: id, modern: modern)
        }
    }

    /// Stops the call the agent gave up on, as `params` names it.
    func cancel(_ params: AgentJSON) {
        guard let request = params["requestId"] else { return }
        calls.removeValue(forKey: Self.key(request))?.cancel()
    }

    private func finish(_ key: String, result: AgentToolResult, id: AgentJSON, modern: Bool) async {
        calls.removeValue(forKey: key)
        send(result: AgentJSON.encoded(result), id: id, modern: modern)
        // Crest lists other tools than this helper knows, as after an update:
        // a legacy agent hears the list changed.
        if let tools = await link.tools, tools != announcedTools {
            announcedTools = tools
            if legacy != nil {
                output.send(
                    Self.json(
                        .object(["jsonrpc": .string("2.0"), "method": .string("notifications/tools/list_changed")])))
            }
        }
    }

    // MARK: - Mutators

    func send(result: AgentJSON, id: AgentJSON, modern: Bool) {
        var body = result
        if modern, case .object(var fields) = body {
            fields["resultType"] = .string("complete")
            if fields["tools"] != nil {
                fields["ttlMs"] = .number(Self.listLifetime)
                fields["cacheScope"] = .string("private")
            }
            fields["_meta"] = .object([Self.metaServer: serverInfo])
            body = .object(fields)
        }
        output.send(Self.json(.object(["jsonrpc": .string("2.0"), "id": id, "result": body])))
    }

    func send(error: Failure, id: AgentJSON) {
        var detail: [String: AgentJSON] = ["code": .number(Double(error.code)), "message": .string(error.message)]
        if let data = error.data { detail["data"] = data }
        output.send(Self.json(.object(["jsonrpc": .string("2.0"), "id": id, "error": .object(detail)])))
    }

    private static func json(_ value: AgentJSON) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    /// A request identity as a key, whether the agent gave a number or text.
    private static func key(_ id: AgentJSON) -> String {
        String(decoding: json(id), as: UTF8.self)
    }
}
