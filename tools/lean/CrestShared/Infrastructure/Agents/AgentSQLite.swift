import Foundation
import SQLite3

/// Persists device-only approvals. Connections, stopped tabs and activity are never written.
final class AgentSQLite {
    private let db: SQLiteConnection
    init(directory: URL) throws {
        db = try SQLiteConnection(directory: directory)
        try db.execute(
            "CREATE TABLE IF NOT EXISTS device_agents (id INTEGER PRIMARY KEY CHECK (id = 0), is_on INTEGER NOT NULL, runs_scripts INTEGER NOT NULL)"
        )
        try db.execute(
            "CREATE TABLE IF NOT EXISTS device_agent_space (space TEXT PRIMARY KEY, position INTEGER NOT NULL)")
        try db.execute(
            "CREATE TABLE IF NOT EXISTS device_agent (position INTEGER PRIMARY KEY, team TEXT, signing TEXT, path TEXT, client TEXT, name TEXT NOT NULL)"
        )
    }
    private func rows(_ sql: String, _ read: (OpaquePointer) throws -> Void) throws {
        try db.statement(sql) { value in
            while true {
                let step = sqlite3_step(value)
                if step == SQLITE_DONE { return }
                guard step == SQLITE_ROW else { throw SQLiteConnection.Failure(code: step) }
                try read(value)
            }
        }
    }
    func read() throws -> AgentPreferences {
        var result = AgentPreferences.off
        try rows("SELECT is_on, runs_scripts FROM device_agents") {
            result.isOn = sqlite3_column_int($0, 0) != 0
            result.runsScripts = sqlite3_column_int($0, 1) != 0
        }
        try rows("SELECT space FROM device_agent_space ORDER BY position") {
            if let id = UUID(uuidString: db.text($0, 0)) { result.spaceIDs.append(id) }
        }
        func optional(_ value: OpaquePointer, _ column: Int32) -> String? {
            sqlite3_column_type(value, column) == SQLITE_NULL ? nil : db.text(value, column)
        }
        try rows("SELECT team, signing, path, client, name FROM device_agent ORDER BY position") {
            let identity = AgentIdentity(
                teamID: optional($0, 0), signingID: optional($0, 1), path: optional($0, 2), client: optional($0, 3))
            if identity.isValid, let name = AgentPreferences.cleanName(db.text($0, 4)) {
                result.agents.append(ApprovedAgent(identity: identity, name: name))
            }
        }
        return result
    }
    private func finish(_ value: OpaquePointer) throws {
        let result = sqlite3_step(value)
        guard result == SQLITE_DONE else { throw SQLiteConnection.Failure(code: result) }
    }
    func save(_ preferences: AgentPreferences) throws {
        try db.execute("BEGIN IMMEDIATE")
        do {
            for table in ["device_agents", "device_agent_space", "device_agent"] {
                try db.execute("DELETE FROM \(table)")
            }
            try db.statement("INSERT INTO device_agents(id,is_on,runs_scripts) VALUES(0,?,?)") {
                try db.check(sqlite3_bind_int($0, 1, preferences.isOn ? 1 : 0))
                try db.check(sqlite3_bind_int($0, 2, preferences.runsScripts ? 1 : 0))
                try finish($0)
            }
            try db.statement("INSERT INTO device_agent_space(space,position) VALUES(?,?)") { value in
                for (position, id) in preferences.spaceIDs.enumerated() {
                    sqlite3_reset(value)
                    sqlite3_clear_bindings(value)
                    try db.bind(value, 1, id.uuidString)
                    try db.check(sqlite3_bind_int64(value, 2, Int64(position)))
                    try finish(value)
                }
            }
            try db.statement("INSERT INTO device_agent(position,team,signing,path,client,name) VALUES(?,?,?,?,?,?)") {
                value in
                for (position, agent) in preferences.agents.enumerated() {
                    sqlite3_reset(value)
                    sqlite3_clear_bindings(value)
                    try db.check(sqlite3_bind_int64(value, 1, Int64(position)))
                    try db.bind(value, 2, agent.identity.teamID)
                    try db.bind(value, 3, agent.identity.signingID)
                    try db.bind(value, 4, agent.identity.path)
                    try db.bind(value, 5, agent.identity.client)
                    try db.bind(value, 6, agent.name)
                    try finish(value)
                }
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }
}
