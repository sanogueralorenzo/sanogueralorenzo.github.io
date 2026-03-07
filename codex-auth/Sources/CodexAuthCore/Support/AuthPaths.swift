import Foundation

public struct AuthPaths {
    public let homeDirectory: URL
    public let codexDirectory: URL
    public let codexAuthFile: URL
    public let codexAuthLockFile: URL
    public let managerDirectory: URL
    public let profilesDirectory: URL
    public let activeAccountIDFile: URL
    public let legacyManagerDirectory: URL
    public let legacyProfilesDirectory: URL

    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
        codexDirectory = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        codexAuthFile = codexDirectory.appendingPathComponent("auth.json")
        codexAuthLockFile = codexDirectory.appendingPathComponent("auth.json.lock")
        managerDirectory = codexDirectory.appendingPathComponent("auth", isDirectory: true)
        profilesDirectory = managerDirectory.appendingPathComponent("profiles", isDirectory: true)
        activeAccountIDFile = managerDirectory.appendingPathComponent("active-account-id")
        legacyManagerDirectory = homeDirectory.appendingPathComponent(".codex-auth", isDirectory: true)
        legacyProfilesDirectory = legacyManagerDirectory.appendingPathComponent("profiles", isDirectory: true)
    }
}
