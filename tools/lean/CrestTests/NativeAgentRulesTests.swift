import Foundation
import XCTest

@testable import Crest

final class NativeAgentRulesTests: XCTestCase {
    private typealias Row = [String: Any]
    private func rows(_ name: String) throws -> [Row] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/native-agent-crest-baseline.json")
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? Row)
        return try XCTUnwrap(all[name] as? [Row])
    }
    private func identity(_ row: Row) -> AgentIdentity {
        AgentIdentity(
            teamID: row["teamId"] as? String, signingID: row["signingId"] as? String, path: row["path"] as? String,
            client: row["client"] as? String)
    }
    private func color(_ row: Row?) -> BrandColor? {
        guard let row else { return nil }
        return BrandColor(
            red: row["red"] as! Double, green: row["green"] as! Double, blue: row["blue"] as! Double,
            alpha: row["alpha"] as! Double)
    }
    private func state(_ row: Row) throws -> AgentSessionState {
        AgentSessionState(
            sessionID: UUID(uuidString: row["sessionId"] as! String)!, identity: identity(row["identity"] as! Row),
            name: row["name"] as! String,
            color: color(row["color"] as? Row), tabIDs: (row["tabIds"] as! [String]).map { UUID(uuidString: $0)! },
            opensWindows: row["opensWindows"] as! Bool,
            activity: try (row["activity"] as! [Row]).map { value in
                let kind = try XCTUnwrap(AgentActivityKind.allCases.first { $0.rawValue == "openedTab" })
                return AgentActivity(
                    kind: kind, subject: value["subject"] as! String, at: Date(timeIntervalSince1970: 0))
            })
    }
    func testNameCleaningAndIdentityNormalizationMatchActualCrestAnswers() throws {
        let names = try rows("names")
        XCTAssertEqual(names.count, 21)
        for row in names {
            let units = (row["input"] as? [Int])?.map { UInt16($0) }
            let input = units.map { String(decoding: $0, as: UTF16.self) }
            XCTAssertEqual(AgentPreferences.cleanName(input), row["output"] as? String)
        }
        let identities = try rows("identities")
        XCTAssertEqual(identities.count, 14)
        for row in identities {
            let native = identity(row["input"] as! Row).normalized
            XCTAssertEqual(native, identity(row["identity"] as! Row))
            XCTAssertEqual(native.isValid, row["valid"] as? Bool)
        }
        let first = AgentIdentity(teamID: nil, signingID: nil, path: "/agent", client: "Café")
        let second = AgentIdentity(teamID: nil, signingID: nil, path: "/agent", client: "Cafe\u{301}")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 2, "Two verified program identities retain their exact spelling.")
    }
    func testEveryConnectionTransitionMatchesActualCrestIncludingLimitsAndStopAcrossConnections() throws {
        let trace = try rows("trace")
        XCTAssertGreaterThan(trace.count, 140)
        var connections = AgentConnections()
        let agent = AgentIdentity(teamID: "TEAM", signingID: "com.example.agent", path: nil, client: nil)
        for (index, row) in trace.enumerated() {
            let session = UUID(uuidString: row["session"] as! String)!
            let tab = UUID(uuidString: row["tab"] as! String)!
            var changed = false
            var failure: String?
            do {
                switch row["action"] as! String {
                case "begin": changed = try connections.begin(session, agent, "Agent")
                case "identify":
                    changed = try connections.identify(session, row["name"] as? String, color(row["color"] as? Row))
                case "claim": changed = try connections.claim(session, tab)
                case "stop": changed = connections.stop(tab)
                case "stopAll": changed = connections.stopAll()
                case "end": changed = connections.end { $0.sessionID == session }
                case "allowWindows": changed = try connections.allowWindows(session)
                case "note":
                    changed = try connections.note(
                        session,
                        AgentActivity(
                            kind: .openedTab, subject: row["subject"] as! String, at: Date(timeIntervalSince1970: 0)))
                case "prune": changed = connections.prune { $0 != tab }
                case "unstop": connections.unstop { _ in true }
                default: return XCTFail("Unknown action")
                }
            } catch {
                switch error {
                case .unknownSession: failure = "UnknownAgentSession"
                case .tabStopped: failure = "AgentTabStopped"
                case .tabUnavailable: failure = "AgentTabUnavailable"
                case .sessionsFull: failure = "AgentSessionsFull"
                default: return XCTFail("Unexpected native failure: \(error)")
                }
            }
            XCTAssertEqual(changed, row["changed"] as? Bool, "Step \(index)")
            XCTAssertEqual(failure, row["failure"] as? String, "Step \(index)")
            XCTAssertEqual(connections.all, try (row["states"] as! [Row]).map(state), "Step \(index)")
            XCTAssertEqual(
                Set(connections.stopped(agent).map { $0.uuidString.lowercased() }), Set(row["stopped"] as! [String]),
                "Step \(index)")
        }
    }
}
