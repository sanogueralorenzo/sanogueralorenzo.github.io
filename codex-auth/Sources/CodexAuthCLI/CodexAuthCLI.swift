import CodexAuthCore
import Foundation

struct CodexAuthCLI {
    private enum Command: CaseIterable {
        case save
        case use
        case list
        case current
        case remove
        case watch
        case help

        var aliases: [String] {
            switch self {
            case .save:
                return ["save", "add"]
            case .use:
                return ["use"]
            case .list:
                return ["list"]
            case .current:
                return ["current"]
            case .remove:
                return ["remove", "rm", "delete"]
            case .watch:
                return ["watch"]
            case .help:
                return ["help", "--help", "-h"]
            }
        }

        var usageLine: String {
            switch self {
            case .save:
                return "save|add <profile> [--path <auth.json> | --from-current]"
            case .use:
                return "use <profile> | use --path <auth.json>"
            case .list:
                return "list [--plain]"
            case .current:
                return "current [--plain]"
            case .remove:
                return "remove|rm|delete <profile>"
            case .watch:
                return "watch <start|stop|status|run>"
            case .help:
                return "help"
            }
        }

        var helpLabel: String {
            switch self {
            case .save:
                return "save|add"
            case .use:
                return "use"
            case .list:
                return "list"
            case .current:
                return "current"
            case .remove:
                return "remove|rm|delete"
            case .watch:
                return "watch"
            case .help:
                return "help"
            }
        }

        var summary: String {
            switch self {
            case .save:
                return "Save a profile from current auth.json or explicit --path"
            case .use:
                return "Apply a saved profile or explicit --path to auth.json"
            case .list:
                return "List saved profiles"
            case .current:
                return "Print current profile and auth metadata"
            case .remove:
                return "Delete a saved profile"
            case .watch:
                return "Manage auth sync watcher (start|stop|status|run)"
            case .help:
                return "Print this help output"
            }
        }

        static func resolve(_ token: String) -> Command? {
            allCases.first { $0.aliases.contains(token) }
        }
    }

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

        guard let commandToken = args.first else {
            printUsage()
            return
        }
        args.removeFirst()
        guard let command = Command.resolve(commandToken) else {
            throw AuthManagerError.ioFailure("Unknown command '\(commandToken)'. Run: codex-auth help")
        }

        switch command {
        case .help:
            printUsage()

        case .list:
            let plain = try parsePlainFlag(args, command: "list")
            try printProfiles(manager, plain: plain)

        case .current:
            let plain = try parsePlainFlag(args, command: "current")
            if plain {
                if let currentProfile = try manager.currentProfileName() {
                    print(currentProfile)
                }
            } else {
                let currentProfile = try manager.currentProfileName() ?? "(untracked)"
                print("Current profile: \(currentProfile)")
                let document = try manager.currentAuthDocument()
                print("auth_mode: \(document.auth_mode)")
                print("account_id: \(masked(document.tokens.account_id))")
            }

        case .save:
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

        case .use:
            guard let first = args.first else {
                throw AuthManagerError.ioFailure("Missing profile name or --path option")
            }

            if first == "--path" {
                guard args.count >= 2 else {
                    throw AuthManagerError.ioFailure("Missing value for --path")
                }
                if args.count > 2 {
                    throw AuthManagerError.ioFailure("Unexpected arguments for use --path: \(args.dropFirst(2).joined(separator: " "))")
                }
                let url = URL(fileURLWithPath: expandPath(args[1]))
                let result = try manager.applyAuthFile(path: url)
                printUseResult(result)
                return
            }
            if args.count > 1 {
                throw AuthManagerError.ioFailure("Unexpected arguments for use: \(args.dropFirst().joined(separator: " "))")
            }

            let result = try manager.applyProfile(name: first)
            printUseResult(result)

        case .remove:
            guard let name = args.first else {
                throw AuthManagerError.ioFailure("Missing profile name")
            }
            if args.count > 1 {
                throw AuthManagerError.ioFailure("Unexpected arguments for remove: \(args.dropFirst().joined(separator: " "))")
            }
            try manager.removeProfile(name: name)
            print("Removed profile '\(name)'")
            try printProfiles(manager, plain: false)

        case .watch:
            guard let action = args.first else {
                throw AuthManagerError.ioFailure("Missing watch action. Use start, stop, status, or run.")
            }
            if args.count > 1 {
                throw AuthManagerError.ioFailure("Unexpected arguments for watch: \(args.dropFirst().joined(separator: " "))")
            }
            try handleWatch(action: action, manager: manager)
        }
    }

    private static func parsePlainFlag(_ args: [String], command: String) throws -> Bool {
        if args.isEmpty {
            return false
        }
        if args.count == 1, args[0] == "--plain" {
            return true
        }
        throw AuthManagerError.ioFailure("Unknown option(s) for \(command): \(args.joined(separator: " "))")
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

    private static func printProfiles(_ manager: ProfileManager, plain: Bool) throws {
        let current = try manager.currentProfileName()
        let profiles = try manager.listProfiles()

        if profiles.isEmpty {
            if !plain {
                print("No saved profiles")
            }
            return
        }

        if plain {
            for name in profiles {
                print(name)
            }
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
        let commands = Command.allCases
        print("Usage:")
        for command in commands {
            print("  codex-auth [--home <dir>] \(command.usageLine)")
        }
        print("")
        print("Commands:")
        let maxLabelLength = commands.map { $0.helpLabel.count }.max() ?? 0
        for command in commands {
            let paddedLabel = command.helpLabel.padding(
                toLength: maxLabelLength,
                withPad: " ",
                startingAt: 0
            )
            print("  \(paddedLabel)  \(command.summary)")
        }
        print("")
        print("Examples:")
        print("  codex-auth save personal")
        print("  codex-auth save work --path ~/secrets/work-auth.json")
        print("  codex-auth use work")
        print("  codex-auth remove personal")
        print("  codex-auth watch start")
    }

    private static func handleWatch(action: String, manager: ProfileManager) throws {
        let watcher = AuthSyncWatcher(homeDirectory: manager.paths.homeDirectory)

        switch action {
        case "start":
            let pid = try watcher.startDaemon(executablePath: CommandLine.arguments[0],
                                              homeDirectory: manager.paths.homeDirectory)
            print("Watcher running (PID \(pid))")
        case "stop":
            try watcher.stopDaemon()
            print("Watcher stopped")
        case "status":
            switch watcher.status() {
            case .stopped:
                print("Watcher stopped")
            case .running(let pid):
                print("Watcher running (PID \(pid))")
            }
        case "run":
            try watcher.runLoop()
        default:
            throw AuthManagerError.ioFailure("Unknown watch action '\(action)'. Use start, stop, status, or run.")
        }
    }
}
