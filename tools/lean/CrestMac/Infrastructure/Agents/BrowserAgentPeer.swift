import Darwin
import Foundation
import Security

/// The program at the other end of an agent connection, as macOS vouches for
/// it: the bundled `crest-browser` helper of this very Crest, whose process
/// started it, and the agent that started the helper. Nothing here comes from
/// what either program says about itself.
struct BrowserAgentPeer: Sendable {
    // MARK: - Types

    /// An agent program as its code signature names it.
    struct Program: Sendable {
        /// The core's key for the program: its team and signing identifier
        /// when a developer signed it, otherwise its path. A general
        /// interpreter's key also takes the name its agent gives.
        let identity: AgentIdentity
        /// What the person knows the program as: its app's name, or its
        /// executable's.
        let name: String
        /// The developer who signed it, as its certificate names them.
        let signer: String?
        let path: String
        /// Whether the program runs other programs' code, such as node or
        /// python, so its signature vouches for nothing it runs.
        let isInterpreter: Bool

        /// What Crest calls the agent once the person allows it: an
        /// interpreter's agent by the name it gives, since the interpreter's
        /// own name says nothing about it.
        var agentName: String { identity.client ?? name }

        /// The program as it vouches for `client`, the agent it runs: an
        /// interpreter's key takes the name the agent gives, which the core
        /// cleans.
        func running(_ client: AgentClientInfo?) -> Self {
            guard isInterpreter, let name = client?.name, !name.isEmpty else { return self }
            return Self(
                identity: AgentIdentity(
                    teamID: identity.teamID, signingID: identity.signingID, path: identity.path, client: name),
                name: self.name, signer: signer, path: path, isInterpreter: true)
        }
    }

    // MARK: - Static Variables

    /// Executables that run code they are handed rather than code of their
    /// own, by their names in lowercase without a version.
    private static let interpreters: Set<String> = [
        "node", "nodejs", "bun", "deno", "python", "pypy", "ruby", "perl", "php", "java", "lua", "tclsh", "uv", "uvx",
        "npx", "pnpm", "yarn", "osascript",
    ]
    /// How far above the helper Crest looks for the agent, past shells and
    /// the system's own programs.
    private static let maximumAncestry = 4

    // MARK: - Variables

    let helperProcessID: pid_t
    let agent: Program?

    // MARK: - Actions - Verification

    /// The peer of `descriptor` when it runs as this user and is this Crest's
    /// own helper, as its audit token and code signature show; nil for any
    /// other process, which is closed before anything is read from it.
    static func verified(_ descriptor: Int32, helper: BrowserAgentHelperRequirement) -> Self? {
        var user: uid_t = 0
        var group: gid_t = 0
        guard getpeereid(descriptor, &user, &group) == 0, user == getuid() else { return nil }
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0,
            helper.isSatisfied(by: token)
        else { return nil }
        // The audit token keeps the process's number in its sixth word, which
        // `audit_token_to_pid` reads.
        let processID = pid_t(bitPattern: token.val.5)
        return Self(helperProcessID: processID, agent: agent(above: processID))
    }

    // MARK: - Actions - Agents

    /// The agent that started process `processID`: its nearest ancestor that
    /// is not a shell or another program of the system's own.
    private static func agent(above processID: pid_t) -> Program? {
        var current = processID
        for _ in 0..<maximumAncestry {
            guard let (parent, started) = parent(of: current), parent > 1,
                let code = code(of: parent), self.parent(of: current)?.1 == started
            else { return nil }
            guard let program = program(code) else {
                current = parent
                continue
            }
            return program
        }
        return nil
    }

    /// The parent of `processID` and when the process started, which tells a
    /// process from one that took its number later.
    private static func parent(of processID: pid_t) -> (pid_t, UInt64)? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(processID, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }
        return (pid_t(info.pbi_ppid), info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec)
    }

    /// The running code of process `processID`.
    private static func code(of processID: pid_t) -> SecCode? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: processID] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else { return nil }
        return code
    }

    /// The program `code` runs, or nil for one of the system's own, such as a
    /// shell, which Crest looks past.
    private static func program(_ code: SecCode) -> Program? {
        var staticCode: SecStaticCode?
        var location: CFURL?
        var info: CFDictionary?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopyPath(staticCode, [], &location) == errSecSuccess, let url = location as URL?,
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
            let signing = info as? [String: Any]
        else { return nil }
        let executable = url.hasDirectoryPath ? (Bundle(url: url)?.executableURL ?? url) : url
        let isInterpreter = isInterpreter(executable.lastPathComponent)
        // A program of the system's own is looked past, unless it runs code it
        // is handed, as osascript and the system's Ruby do.
        let isPlatform = (signing[kSecCodeInfoPlatformIdentifier as String] as? Int ?? 0) != 0
        if isPlatform && !isInterpreter { return nil }
        let team = (signing[kSecCodeInfoTeamIdentifier as String] as? String).flatMap(teamID)
        let signingID = signing[kSecCodeInfoIdentifier as String] as? String
        // What the signature says counts only when macOS finds it valid and
        // issued by Apple, to the team it names or to Apple for its own
        // programs. Any other program, such as one signed with a certificate
        // its maker made, is known only by where it is.
        let vouched = isValid(code, team: team)
        let bundleName = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
        // An app goes by its own name. A lone program a developer signed goes
        // by the identifier they gave it, which outlives its file: Claude Code
        // keeps each version in a file named for the version.
        let name =
            if url.pathExtension == "app" {
                bundleName ?? url.deletingPathExtension().lastPathComponent
            } else if vouched, team != nil, let named = signingID?.split(separator: ".").last {
                String(named)
            } else {
                url.lastPathComponent
            }
        var signer: String?
        if vouched, let certificates = signing[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leaf = certificates.first, let summary = SecCertificateCopySubjectSummary(leaf) as String?
        {
            // "Developer ID Application: Anthropic PBC (Q6L2SF6YDW)" names
            // Anthropic PBC; Apple signs its own programs as "Software Signing".
            signer =
                summary == "Software Signing"
                ? "Apple" : summary.components(separatedBy: ": ").last?.components(separatedBy: " (").first ?? summary
        }
        let identity =
            if vouched, let team, let signingID {
                AgentIdentity(teamID: team, signingID: signingID, path: nil, client: nil)
            } else {
                AgentIdentity(teamID: nil, signingID: nil, path: executable.path, client: nil)
            }
        return Program(
            identity: identity, name: name, signer: signer, path: executable.path, isInterpreter: isInterpreter)
    }

    /// Whether the running `code` is valid and signed through Apple: by Apple
    /// itself, or with a Developer ID or App Store certificate of `team`.
    private static func isValid(_ code: SecCode, team: String?) -> Bool {
        var text = "anchor apple"
        if let team { text += " or (anchor apple generic and certificate leaf[subject.OU] = \"\(team)\")" }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement
        else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    /// `text` when it is a team identifier, ten capital letters and digits as
    /// Apple issues them, and nil otherwise; a signature's maker chooses what
    /// it says, so nothing else reaches a requirement.
    private static func teamID(_ text: String) -> String? {
        text.count == 10 && text.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) } ? text : nil
    }

    /// Whether `executable` names an interpreter, with or without a version,
    /// as python3.14 and node22 do.
    private static func isInterpreter(_ executable: String) -> Bool {
        let unversioned = executable.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-"))
        return interpreters.contains(unversioned)
    }
}

/// What the program at the other end of the agent socket must be: this
/// Crest's own bundled helper, by the designated requirement of the copy
/// inside this app, whatever signed it.
struct BrowserAgentHelperRequirement: @unchecked Sendable {
    // MARK: - Variables

    let path: String
    private let requirement: SecRequirement

    // MARK: - Initializers

    /// The requirement of the helper inside `bundle`, or nil when the app
    /// carries none it can read.
    init?(bundle: Bundle) {
        let helper = bundle.bundleURL.appendingPathComponent("Contents/Helpers/crest-browser", isDirectory: false)
            .resolvingSymlinksInPath()
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(helper as CFURL, [], &code) == errSecSuccess, let code,
            SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement
        else { return nil }
        path = helper.path
        self.requirement = requirement
    }

    // MARK: - Actions - Verification

    /// Whether the process `token` names runs, unchanged since it started, the
    /// helper this requirement describes, from inside this app.
    func isSatisfied(by token: audit_token_t) -> Bool {
        var token = token
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: data] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
            SecCodeCheckValidity(code, [], requirement) == errSecSuccess
        else { return false }
        var staticCode: SecStaticCode?
        var location: CFURL?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopyPath(staticCode, [], &location) == errSecSuccess, let url = location as URL?
        else { return false }
        return url.resolvingSymlinksInPath().path == path
    }
}
