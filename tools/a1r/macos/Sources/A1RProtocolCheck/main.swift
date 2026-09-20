import Foundation
import A1RProtocol

let data = Data(#"{"v":1,"seq":2,"requestId":"r1","event":{"type":"text_delta","delta":"hello"}}"#.utf8)
let envelope = try JSONDecoder().decode(RuntimeEnvelope.self, from: data)
guard envelope.seq == 2,
      envelope.event.type == "text_delta",
      envelope.event.delta == "hello" else {
    fatalError("A1R protocol decoding check failed")
}
let request = try JSONEncoder().encode(ChatRequest(text: "hello", sessionId: nil, requestId: "r1", fresh: true))
guard String(decoding: request, as: UTF8.self).contains("\"fresh\":true") else {
    fatalError("A1R new-session protocol check failed")
}
let setupData = Data(#"{"configured":false,"selectedBackend":null,"recommendedBackend":"codex","openAIConfigured":false,"codex":{"installed":true,"connected":true,"planType":"plus","allowanceAvailable":true,"usage":[{"name":"Codex","usedPercent":25,"remainingPercent":75,"resetsAt":1893456000}],"error":null}}"#.utf8)
let setup = try JSONDecoder().decode(SetupStatus.self, from: setupData)
guard setup.codex.connected,
      setup.codex.planType == "plus",
      setup.codex.usage.first?.remainingPercent == 75 else {
    fatalError("A1R Codex setup protocol check failed")
}
let loginData = Data(#"{"type":"chatgpt","loginId":"login-1","authUrl":"https://auth.openai.com/fake"}"#.utf8)
let login = try JSONDecoder().decode(CodexLoginStart.self, from: loginData)
guard login.type == "chatgpt", login.loginId == "login-1", login.authUrl.hasPrefix("https://") else {
    fatalError("A1R browser-login protocol check failed")
}
print("A1R protocol check passed")
