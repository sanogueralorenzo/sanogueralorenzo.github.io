import Foundation

#if os(macOS)
    /// What a watched page's activity observer posted, as it spells it, and
    /// how an agent watching the page keeps it.
    struct WebKitAgentActivityKind: Decodable, Sendable {
        // MARK: - Static Variables

        /// A console message or an error.
        static let console = Self(name: "console") { message, activity in
            activity.consoleSequence += 1
            activity.console.append(
                PageConsoleMessage(
                    sequence: activity.consoleSequence, level: message.level?.engineLevel ?? .log,
                    text: String((message.text ?? "").prefix(WebKitPageAgents.maximumText)),
                    source: message.source.map { String($0.prefix(WebKitPageAgents.maximumText)) },
                    line: message.line ?? 0, at: Date()))
            if activity.console.count > WebKitPageAgents.maximumKept {
                activity.console.removeFirst()
                activity.consoleDropped += 1
            }
        }

        /// A resource the page loaded.
        static let network = Self(name: "network") { message, activity in
            activity.networkSequence += 1
            activity.network.append(
                PageNetworkRequest(
                    sequence: activity.networkSequence,
                    url: String((message.url ?? "").prefix(WebKitPageAgents.maximumText)),
                    method: "", resourceType: message.type ?? "", status: message.status ?? 0, mimeType: nil,
                    requestHeaders: [], responseHeaders: [],
                    started: message.start.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(),
                    duration: message.duration ?? 0, bytes: Int64(message.bytes ?? 0), failure: nil))
            if activity.network.count > WebKitPageAgents.maximumKept {
                activity.network.removeFirst()
                activity.networkDropped += 1
            }
        }

        static let all: [WebKitAgentActivityKind] = [console, network]

        // MARK: - Variables

        let name: String
        private let keeping: @MainActor @Sendable (WebKitAgentActivityMessage, inout WebKitPageAgents.Activity) -> Void

        // MARK: - Initializers

        private init(
            name: String,
            keeping:
                @escaping @MainActor @Sendable (WebKitAgentActivityMessage, inout WebKitPageAgents.Activity) -> Void
        ) {
            self.name = name
            self.keeping = keeping
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let name = try container.decode(String.self)
            guard let kind = Self.all.first(where: { $0.name == name }) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "The observer posts no activity \(name).")
            }
            self = kind
        }

        // MARK: - Actions - Activity

        /// Keeps `message`, one of this kind, in the activity an agent
        /// watching the page keeps.
        @MainActor
        func keep(_ message: WebKitAgentActivityMessage, in activity: inout WebKitPageAgents.Activity) {
            keeping(message, &activity)
        }
    }
#endif
