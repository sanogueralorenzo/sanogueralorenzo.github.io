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
print("A1R protocol check passed")
