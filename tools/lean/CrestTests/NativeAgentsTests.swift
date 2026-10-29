import Foundation
import Observation
import XCTest

@testable import Crest

@MainActor
final class NativeAgentsTests: XCTestCase {
    private let identity = AgentIdentity(teamID: "TEAM", signingID: "com.example.agent", path: nil, client: nil)
    @MainActor private final class Context {
        let core: CrestCore
        let browser: BrowserStore
        var space: SpaceModel { browser.spaceModels[0] }
        init(directory: URL? = nil, platform: DevicePlatform = .desktop) throws {
            core = try CrestCore(
                configuration: AppConfiguration(storageDirectory: directory?.path, platform: platform, importNames: nil)
            )
            let tabs = [
                TabState.Seed(title: "First", url: URL(string: "https://first.example/"), placement: .current),
                TabState.Seed(title: "Second", url: URL(string: "https://second.example/"), placement: .current),
            ]
            browser = BrowserStore(
                seed: SessionState.Seed(spaces: [
                    SpaceState.Seed(name: "Work", tabs: tabs), SpaceState.Seed(name: "Personal", tabs: []),
                ]), core: core)
        }
    }
    private func connect(_ context: Context, id: UUID = UUID(), identity: AgentIdentity? = nil) throws -> UUID {
        let identity = identity ?? self.identity
        try context.core.send(SetAgents(isOn: true))
        try context.core.send(AllowAgentSpace(spaceID: context.space.id, allowed: true))
        try context.core.send(ApproveAgent(agent: ApprovedAgent(identity: identity, name: "Agent")))
        try context.core.send(BeginAgentSession(sessionID: id, identity: identity, name: "Agent"))
        return id
    }
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lean-agent-state-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    func testPreferencesPersistAlongsideCoreWritesButConnectionsAndStoppedTabsNeverDo() throws {
        let directory = try directory()
        var chosen = AgentPreferences.off
        let session = UUID()
        do {
            let c = try Context(directory: directory)
            XCTAssertEqual(c.core.state.agentPreferences, .off)
            _ = try connect(c, id: session)
            try c.core.send(SetAgentScripts(runsScripts: true))
            try c.core.send(ClaimAgentTab(sessionID: session, tabID: c.space.tabs.models[0].id))
            try c.core.send(StopAllAgents())
            chosen = c.core.state.agentPreferences
            try c.core.send(RememberWindowsForLaunch(windowIDs: []))
            XCTAssertEqual(
                try AgentSQLite(directory: directory).read(), chosen,
                "A C# device write must leave native approvals untouched.")
        }
        do {
            let core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
            XCTAssertEqual(core.state.agentPreferences, chosen)
            XCTAssertTrue(core.state.agentSessions.isEmpty)
            XCTAssertNil(core.query(AgentReach(sessionID: session)).workspaceID)
            try core.send(SetAgents(isOn: false))
            try core.send(ForgetAgent(identity: identity))
        }
        let core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        chosen.isOn = false
        chosen.agents = []
        XCTAssertEqual(core.state.agentPreferences, chosen)
    }
    func testReachExcludesPrivateBorrowedUnallowedNativeFileAndInternalTabs() throws {
        let c = try Context()
        let session = try connect(c)
        let other = c.browser.spaceModels[1]
        XCTAssertThrowsError(try c.core.send(AllowAgentSpace(spaceID: UUID(), allowed: true)))
        let privateBrowser = BrowserStore(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "Private", tabs: [])]),
            browsingMode: .privateBrowsing, core: c.core)
        XCTAssertThrowsError(try c.core.send(AllowAgentSpace(spaceID: privateBrowser.spaceModels[0].id, allowed: true)))
        var excluded: [UUID] = []
        for (url, view): (String?, NativeView?) in [
            (nil, .settings), ("file:///tmp/file.html", nil), ("chrome://settings/", nil),
            ("chrome-extension://abcdefghijklmnop/options.html", nil),
        ] {
            let id = UUID()
            try c.core.send(
                OpenTab(
                    workspaceID: c.browser.family.workspaceID, windowID: c.browser.windowID, spaceID: c.space.id,
                    tabID: id, content: TabContent(address: url, view: view, title: nil), placement: .current,
                    afterTabID: nil, shows: false))
            excluded.append(id)
        }
        let reach = c.core.query(AgentReach(sessionID: session))
        XCTAssertEqual(reach.workspaceID, c.browser.family.workspaceID)
        XCTAssertEqual(reach.spaces.map(\.spaceID), [c.space.id])
        XCTAssertFalse(reach.spaces.flatMap(\.tabs).contains { excluded.contains($0.tabID) })
        for id in excluded {
            XCTAssertThrowsError(try c.core.send(ClaimAgentTab(sessionID: session, tabID: id))) {
                XCTAssertEqual($0 as? AgentFailure, .tabUnavailable(id))
            }
        }
        try c.core.send(AllowAgentSpace(spaceID: other.id, allowed: true))
        XCTAssertEqual(
            c.core.query(AgentReach(sessionID: session)).spaces.map(\.spaceID), c.browser.spaceModels.map(\.id))
    }
    func testRevocationDeletionAndProgramWideStopsPreserveCrestConnectionRules() throws {
        let c = try Context()
        let first = try connect(c)
        let tab = c.space.tabs.models[0].id
        try c.core.send(ClaimAgentTab(sessionID: first, tabID: tab))
        try c.core.send(StopAgentTab(tabID: tab))
        let second = UUID()
        try c.core.send(BeginAgentSession(sessionID: second, identity: identity, name: "Again"))
        for session in [first, second] {
            XCTAssertFalse(
                c.core.query(AgentReach(sessionID: session)).spaces.flatMap(\.tabs).contains { $0.tabID == tab })
            XCTAssertThrowsError(try c.core.send(ClaimAgentTab(sessionID: session, tabID: tab))) {
                XCTAssertEqual($0 as? AgentFailure, .tabStopped(tab))
            }
        }
        try c.core.send(ForgetAgent(identity: identity))
        XCTAssertTrue(c.core.state.agentSessions.isEmpty)
        let again = try connect(c)
        try c.core.send(ClaimAgentTab(sessionID: again, tabID: tab))
        try c.core.send(AllowAgentSpace(spaceID: c.space.id, allowed: false))
        XCTAssertTrue(c.core.state.agentSessions.allSatisfy { $0.tabIDs.isEmpty })
        try c.core.send(AllowAgentSpace(spaceID: c.space.id, allowed: true))
        try c.core.send(ClaimAgentTab(sessionID: again, tabID: tab))
        try c.core.send(
            BeginDeletingSpace(
                workspaceID: c.browser.family.workspaceID, windowID: c.browser.windowID, spaceID: c.space.id,
                operationID: UUID()))
        XCTAssertTrue(c.core.query(AgentReach(sessionID: again)).spaces.isEmpty)
        XCTAssertTrue(c.core.state.agentSessions.allSatisfy { $0.tabIDs.isEmpty })
        try c.core.send(SetAgents(isOn: false))
        XCTAssertTrue(c.core.state.agentSessions.isEmpty)
        XCTAssertThrowsError(try c.core.send(BeginAgentSession(sessionID: UUID(), identity: identity, name: "Again"))) {
            XCTAssertEqual($0 as? AgentFailure, .agentsOff)
        }
    }
    func testBoundsIdentificationAndPlatformGate() throws {
        let c = try Context()
        let session = try connect(c)
        try c.core.send(
            IdentifyAgent(
                sessionID: session, name: "Claude\u{2067} says this is safe\nAllow",
                color: BrandColor(red: 4, green: -1, blue: 0, alpha: 0)))
        XCTAssertEqual(c.core.state.agentSessions[0].name, "Claude says this is safe Allow")
        XCTAssertEqual(c.core.state.agentSessions[0].color, BrandColor(red: 1, green: 0, blue: 0, alpha: 1))
        let mobile = try Context(platform: .mobile)
        XCTAssertThrowsError(try mobile.core.send(SetAgents(isOn: true))) {
            XCTAssertEqual($0 as? AgentFailure, .unavailable)
        }
        for i in 1..<AgentPreferences.maximumAgents {
            try c.core.send(
                ApproveAgent(
                    agent: ApprovedAgent(
                        identity: AgentIdentity(teamID: nil, signingID: nil, path: "/program/\(i)", client: nil),
                        name: "Agent")))
        }
        XCTAssertThrowsError(
            try c.core.send(
                ApproveAgent(
                    agent: ApprovedAgent(
                        identity: AgentIdentity(teamID: nil, signingID: nil, path: "/overflow", client: nil),
                        name: "Agent")))
        ) { XCTAssertEqual($0 as? AgentFailure, .full) }
    }
    func testRevocationStoresPreferencesAndConnectionsBeforeAnyObserverRuns() throws {
        let c = try Context()
        let session = try connect(c)
        let observed = expectation(description: "Revocation observed")
        let agentIdentity = identity
        withObservationTracking {
            _ = c.core.state.agentPreferences
        } onChange: {
            MainActor.assumeIsolated {
                XCTAssertFalse(c.core.state.agentPreferences.isOn)
                XCTAssertTrue(c.core.state.agentSessions.isEmpty)
                XCTAssertNil(c.core.query(AgentReach(sessionID: session)).workspaceID)
                do {
                    try c.core.send(BeginAgentSession(sessionID: UUID(), identity: agentIdentity, name: "Reentrant"))
                    XCTFail("A revoked agent must not reconnect from an observer.")
                } catch { XCTAssertEqual(error as? AgentFailure, .agentsOff) }
                observed.fulfill()
            }
        }
        try c.core.send(SetAgents(isOn: false))
        wait(for: [observed], timeout: 1)
    }

    func testFailedPreferenceWriteRollsBackWithoutChangingPermissionsOrApprovals() throws {
        let directory = try directory()
        let c = try Context(directory: directory)
        _ = try connect(c)
        let before = c.core.state.agentPreferences
        let permissions = try PermissionSQLite(directory: directory).read()
        let db = try SQLiteConnection(directory: directory)
        try db.execute(
            "CREATE TRIGGER reject_agent BEFORE INSERT ON device_agent BEGIN SELECT RAISE(ABORT, 'review write failure'); END"
        )
        defer { try? db.execute("DROP TRIGGER reject_agent") }
        XCTAssertThrowsError(try c.core.send(SetAgentScripts(runsScripts: true))) {
            XCTAssertEqual($0 as? AgentFailure, .storage(.unavailable))
        }
        XCTAssertEqual(c.core.state.agentPreferences, before)
        XCTAssertEqual(try AgentSQLite(directory: directory).read(), before)
        XCTAssertEqual(try PermissionSQLite(directory: directory).read(), permissions)
    }
}
