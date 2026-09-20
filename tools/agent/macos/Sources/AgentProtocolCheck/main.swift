import Foundation
import AgentProtocol

func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }

let event = try JSONDecoder().decode(RuntimeEvent.self, from: Data(#"{"type":"text_delta","delta":"hello"}"#.utf8))
check(event.type == "text_delta" && event.delta == "hello", "Agent protocol decoding check failed")
let artifact = try JSONDecoder().decode(RuntimeEvent.self, from: Data(#"{"type":"artifact","artifact":{"id":"a1","kind":"image","name":"result.png","mimeType":"image/png","size":12,"path":"/tmp/result.png"}}"#.utf8))
check(artifact.artifact?.name == "result.png", "Agent artifact protocol check failed")
let request = try JSONEncoder().encode(ChatRequest(text: "hello", sessionId: nil, requestId: "r1", fresh: true))
check(String(decoding: request, as: UTF8.self).contains("\"fresh\":true"), "Agent new-session protocol check failed")
let setup = try JSONDecoder().decode(SetupStatus.self, from: Data(#"{"configured":false,"selectedBackend":null,"openAIConfigured":false,"codex":{"installed":true,"connected":true,"planType":"plus"}}"#.utf8))
check(setup.codex.connected, "Agent Codex setup protocol check failed")
let login = try JSONDecoder().decode(CodexLoginStart.self, from: Data(#"{"type":"chatgpt","loginId":"login-1","authUrl":"https://auth.openai.com/fake"}"#.utf8))
check(login.type == "chatgpt" && login.loginId == "login-1" && login.authUrl?.hasPrefix("https://") == true, "Agent browser-login protocol check failed")
print("Agent protocol check passed")
