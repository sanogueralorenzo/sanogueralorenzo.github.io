import Foundation

struct AuthenticationAsked: CorePromptChange, Equatable, Sendable {
    let promptID: UUID
    let pageID: UUID
    let question: AuthenticationQuestion
    @MainActor func present(on host: any CorePromptHost) { host.ask(self) }
}

struct AuthenticationChallenged: PromptEvent, Equatable, Sendable {
    let promptID: UUID
    let pageID: UUID
    let question: AuthenticationQuestion
}

struct AuthenticationQuestion: Equatable, Sendable {
    var url: String
    var host: String
    var port: Int
    var realm: String?
    var scheme: AuthenticationScheme
    var isProxy: Bool
    var previousFailures: Int
}

struct AuthenticationCredential: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    var username: String
    var password: String
    var description: String { "AuthenticationCredential(<redacted>)" }
    var debugDescription: String { description }
}

struct ExtensionInstallAsked: CorePromptChange, Equatable, Sendable {
    let promptID: UUID
    let windowID: UUID
    let question: ExtensionInstallQuestion
    @MainActor func present(on host: any CorePromptHost) { host.ask(self) }
}

struct ExtensionInstallQuestion: Equatable, Sendable {
    var extensionID: String
    var name: String
    var version: String
    var summary: String
    var permissions: [String]
    var icon: Data?
    var canWithholdSiteAccess: Bool
    var withholdsSiteAccess: Bool
}

struct ExtensionInstallRequested: PromptEvent, Equatable, Sendable {
    let promptID: UUID
    let windowID: UUID
    let question: ExtensionInstallQuestion
}

struct PermissionAsked: CorePromptChange, Equatable, Sendable {
    let promptID: UUID
    let pageID: UUID
    let question: PermissionQuestion
    @MainActor func present(on host: any CorePromptHost) { host.ask(self) }
}

struct PermissionQuestion: Equatable, Sendable {
    var permission: SitePermission
    var origin: SiteOrigin
    var topLevelOrigin: SiteOrigin
}

struct PermissionRequested: PromptEvent, Equatable, Sendable {
    let promptID: UUID
    let pageID: UUID
    let question: PermissionQuestion
}

struct ScriptDialogAsked: CorePromptChange, Equatable, Sendable {
    let promptID: UUID
    let pageID: UUID
    let question: ScriptDialogQuestion
    @MainActor func present(on host: any CorePromptHost) { host.ask(self) }
}

struct ScriptDialogQuestion: Equatable, Sendable {
    var kind: JavaScriptDialogKind
    var message: String
    var defaultText: String
    var sourceURL: String
}

struct ScriptDialogOpened: PromptEvent, Equatable, Sendable {
    let promptID: UUID
    let pageID: UUID
    let question: ScriptDialogQuestion
}

struct PromptWithdrawn: PromptEvent, Equatable, Sendable {
    let promptID: UUID
}

struct AnswerAuthentication: PromptIntent, Equatable, Sendable {
    let promptID: UUID
    let credential: AuthenticationCredential?
}

struct AnswerPermission: PromptIntent, Equatable, Sendable {
    let promptID: UUID
    let grants: Bool
    let remembers: Bool
}

struct AnswerScriptDialog: PromptIntent, Equatable, Sendable {
    let promptID: UUID
    let accepted: Bool
    let text: String?
}

struct AnswerExtensionInstall: PromptIntent, Equatable, Sendable {
    let promptID: UUID
    let accepted: Bool
    let withholdsSiteAccess: Bool
}

struct SettleAuthentication: Equatable, Sendable {
    let promptID: UUID
    let credential: AuthenticationCredential?
}

struct SettlePermission: Equatable, Sendable {
    let promptID: UUID
    let grants: Bool
    let remembers: Bool
}

struct SettleScriptDialog: Equatable, Sendable {
    let promptID: UUID
    let accepted: Bool
    let text: String?
}

struct SettleExtensionInstall: Equatable, Sendable {
    let promptID: UUID
    let accepted: Bool
    let withholdsSiteAccess: Bool
}

enum AuthenticationScheme: Int, CaseIterable, Sendable {
    case basic = 0
    case digest = 1
}

enum JavaScriptDialogKind: Int, CaseIterable, Sendable {
    case alert = 0
    case confirm = 1
    case prompt = 2
    case beforeUnload = 3
}
