import Foundation
import AgentProtocol

let data = Data(#"{"type":"text_delta","delta":"hello"}"#.utf8)
let event = try JSONDecoder().decode(RuntimeEvent.self, from: data)
guard event.type == "text_delta", event.delta == "hello" else {
    fatalError("Agent protocol decoding check failed")
}
let artifactData = Data(#"{"type":"artifact","artifact":{"id":"a1","kind":"image","name":"result.png","mimeType":"image/png","size":12,"path":"/tmp/result.png"}}"#.utf8)
let artifact = try JSONDecoder().decode(RuntimeEvent.self, from: artifactData)
guard artifact.artifact?.name == "result.png" else {
    fatalError("Agent artifact protocol check failed")
}
let request = try JSONEncoder().encode(ChatRequest(text: "hello", sessionId: nil, requestId: "r1", fresh: true))
guard String(decoding: request, as: UTF8.self).contains("\"fresh\":true") else {
    fatalError("Agent new-session protocol check failed")
}
let setupData = Data(#"{"configured":false,"selectedBackend":null,"openAIConfigured":false,"codex":{"installed":true,"connected":true,"planType":"plus"}}"#.utf8)
let setup = try JSONDecoder().decode(SetupStatus.self, from: setupData)
guard setup.codex.connected else {
    fatalError("Agent Codex setup protocol check failed")
}
let loginData = Data(#"{"type":"chatgpt","loginId":"login-1","authUrl":"https://auth.openai.com/fake"}"#.utf8)
let login = try JSONDecoder().decode(CodexLoginStart.self, from: loginData)
guard login.type == "chatgpt", login.loginId == "login-1", login.authUrl?.hasPrefix("https://") == true else {
    fatalError("Agent browser-login protocol check failed")
}
print("Agent protocol check passed")
