import CodexAuthCore
import Foundation

struct CodexAuthCLI {
    static func main() {
        do {
            try run()
        } catch {
            let message: String
            if let localized = error as? LocalizedError, let desc = localized.errorDescription {
                message = desc
            } else {
                message = String(describing: error)
            }
            fputs("Error: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        let customHome = try parseGlobalHomeFlag(&args)
        let manager = customHome.map { ProfileManager(homeDirectory: $0) } ?? ProfileManager()

        guard let command = args.first else {
            printUsage()
            return
        }
        args.removeFirst()

        switch command {
        case "help", "--help", "-h":
            printUsage()

        case "list":
            try printProfiles(manager)

        case "current":
            let currentProfile = try manager.currentProfileName() ?? "(untracked)"
            print("Current profile: \(currentProfile)")
            let document = try manager.currentAuthDocument()
            print("auth_mode: \(document.auth_mode)")
            print("account_id: \(masked(document.tokens.account_id))")

        case "save", "add":
            guard let name = args.first else {
                throw AuthManagerError.ioFailure("Missing profile name. Example: codex-auth save personal")
            }
            args.removeFirst()
            let source = try parseSaveSource(args)

            let before = try manager.listProfiles()
            if before.isEmpty {
                print("Existing profiles: (none)")
            } else {
                print("Existing profiles: \(before.joined(separator: ", "))")
            }

            let savedName = try manager.saveProfile(name: name, source: source)
            print("Saved profile '\(savedName)'")

            let after = try manager.listProfiles()
            print("Available profiles: \(after.joined(separator: ", "))")

        case "use":
            guard let first = args.first else {
                throw AuthManagerError.ioFailure("Missing profile name or --path option")
            }

            if first == "--path" {
                guard args.count >= 2 else {
                    throw AuthManagerError.ioFailure("Missing value for --path")
                }
                let url = URL(fileURLWithPath: expandPath(args[1]))
                let result = try manager.applyAuthFile(path: url)
                printUseResult(result)
                return
            }

            let result = try manager.applyProfile(name: first)
            printUseResult(result)

        case "remove", "rm", "delete":
            guard let name = args.first else {
                throw AuthManagerError.ioFailure("Missing profile name")
            }
            try manager.removeProfile(name: name)
            print("Removed profile '\(name)'")
            try printProfiles(manager)

        default:
            throw AuthManagerError.ioFailure("Unknown command '\(command)'. Run: codex-auth help")
        }
    }

    private static func parseSaveSource(_ args: [String]) throws -> ProfileSource {
        if args.isEmpty {
            return .current
        }

        var i = 0
        var selected: ProfileSource = .current

        while i < args.count {
            switch args[i] {
            case "--path":
                guard i + 1 < args.count else {
                    throw AuthManagerError.ioFailure("Missing value for --path")
                }
                selected = .path(URL(fileURLWithPath: expandPath(args[i + 1])))
                i += 2
            case "--from-current":
                selected = .current
                i += 1
            default:
                throw AuthManagerError.ioFailure("Unknown option '\(args[i])' for save")
            }
        }

        return selected
    }

    private static func parseGlobalHomeFlag(_ args: inout [String]) throws -> URL? {
        guard let first = args.first, first == "--home" else {
            return nil
        }
        guard args.count >= 2 else {
            throw AuthManagerError.ioFailure("Missing value for --home")
        }
        let url = URL(fileURLWithPath: expandPath(args[1]))
        args.removeFirst(2)
        return url
    }

    private static func printProfiles(_ manager: ProfileManager) throws {
        let current = try manager.currentProfileName()
        let profiles = try manager.listProfiles()

        if profiles.isEmpty {
            print("No saved profiles")
            return
        }

        print("Profiles:")
        for name in profiles {
            if name == current {
                print("* \(name)")
            } else {
                print("  \(name)")
            }
        }
    }

    private static func printUseResult(_ result: SwitchResult) {
        print("Applied auth from \(result.sourceDescription)")
        if let backup = result.backup {
            print("Backup saved: \(backup.path)")
        }
        print("Updated: \(result.destination.path)")
        let invalidation = result.invalidation
        if invalidation.hadTargets {
            print("Invalidated Codex sessions:")
            print("  app processes terminated: \(invalidation.terminatedAppPIDs.count)")
            print("  cli processes terminated: \(invalidation.terminatedCliPIDs.count)")
            if !invalidation.terminatedAppPIDs.isEmpty {
                print("  app PIDs: \(invalidation.terminatedAppPIDs.map(String.init).joined(separator: ", "))")
            }
            if !invalidation.terminatedCliPIDs.isEmpty {
                print("  cli PIDs: \(invalidation.terminatedCliPIDs.map(String.init).joined(separator: ", "))")
            }
            if !invalidation.failedPIDs.isEmpty {
                print("  failed to terminate PIDs: \(invalidation.failedPIDs.map(String.init).joined(separator: ", "))")
            }
        } else {
            print("No running Codex app/CLI sessions were detected.")
        }
    }

    private static func masked(_ value: String) -> String {
        guard value.count > 8 else {
            return String(repeating: "*", count: value.count)
        }
        let prefix = value.prefix(4)
        let suffix = value.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private static func expandPath(_ raw: String) -> String {
        (raw as NSString).expandingTildeInPath
    }

    private static func printUsage() {
        print("""
Usage:
  codex-auth [--home <dir>] save <profile> [--path <auth.json> | --from-current]
  codex-auth [--home <dir>] add <profile> [--path <auth.json> | --from-current]
  codex-auth [--home <dir>] use <profile>
  codex-auth [--home <dir>] use --path <auth.json>
  codex-auth [--home <dir>] list
  codex-auth [--home <dir>] current
  codex-auth [--home <dir>] remove <profile>
  codex-auth [--home <dir>] help

Examples:
  codex-auth save personal
  codex-auth save work --path ~/secrets/work-auth.json
  codex-auth use work
  codex-auth remove personal
""")
    }
}
