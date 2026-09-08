import Foundation

@MainActor
extension RewriteTests {
    static func piRequests() async throws {
        for kind in RewriteProvider.allCases {
            let configuration = RewriteConfiguration(kind: kind)
            let args = PiService.arguments(configuration)
            check(args.contains(kind.providerID) && args.contains(kind.preferredModel), "explicit provider and model")
            check(PiService.isolationArguments.allSatisfy(args.contains), "isolated Pi request")
            check(args.contains(Editing.rules) && configuration.thinking == "off" && args.contains("off"), "rewrite system prompt and thinking off")
        }
        let priorityRequest = try PiRequest(provider: "openai-codex", credential: "fixture")
        let priorityArgs = try priorityRequest.rewriteArguments(RewriteConfiguration(kind: .openai))
        check(priorityArgs.contains("--extension") && priorityArgs.contains("--no-extensions"), "only explicit rewrite extension loaded")
        let anthropicArgs = try priorityRequest.rewriteArguments(RewriteConfiguration(kind: .anthropic))
        check(!anthropicArgs.contains("--extension"), "OpenAI priority is not sent to Anthropic")
        check(RewriteProvider.saved("Codex CLI") == .openai && RewriteProvider.saved("Claude CLI") == .anthropic, "CLI preferences migrate to Pi providers")
        check(RewriteProvider.saved("Ollama (local)") == nil && RewriteProvider.allCases.count == 2, "local preference requires new setup")
        var request: PiRequest? = try PiRequest(provider: "anthropic", credential: "disposable-fixture-token")
        let requestDirectory = request!.directory
        let names = try FileManager.default.contentsOfDirectory(atPath: requestDirectory.path)
        check(Set(names) == Set(["auth.json", "settings.json"]), "no inherited settings, models, prompts, extensions, or history")
        let permissions = try FileManager.default.attributesOfItem(atPath: requestDirectory.appendingPathComponent("auth.json").path)[.posixPermissions] as? Int
        check(permissions == 0o600, "private temporary credential")
        request = nil
        check(!FileManager.default.fileExists(atPath: requestDirectory.path), "temporary credentials removed")
    }
}
