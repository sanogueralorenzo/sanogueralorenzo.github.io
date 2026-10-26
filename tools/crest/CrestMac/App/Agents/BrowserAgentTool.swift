import Foundation

/// A tool an agent may call: the definition agents discover, and the work
/// Crest does for it. A new tool is a definition in the shared catalog and an
/// instance here.
@MainActor
struct BrowserAgentTool {
    // MARK: - Static Variables

    static let identify = Self(.identify, BrowserMacAgents.identify)
    static let listSpaces = Self(.listSpaces, BrowserMacAgents.listSpaces)
    static let listTabs = Self(.listTabs, BrowserMacAgents.listTabs)
    static let openTab = Self(.openTab, BrowserMacAgents.openTab)
    static let navigate = Self(.navigate, BrowserMacAgents.navigate)
    static let showTab = Self(.showTab, BrowserMacAgents.showTab)
    static let closeTab = Self(.closeTab, BrowserMacAgents.closeTab)
    static let takeSnapshot = Self(.takeSnapshot, BrowserMacAgents.takeSnapshot)
    static let screenshot = Self(.screenshot, BrowserMacAgents.screenshot)
    static let click = Self(.click, BrowserMacAgents.click)
    static let hover = Self(.hover, BrowserMacAgents.hover)
    static let fill = Self(.fill, BrowserMacAgents.fill)
    static let typeText = Self(.typeText, BrowserMacAgents.typeText)
    static let pressKey = Self(.pressKey, BrowserMacAgents.pressKey)
    static let scroll = Self(.scroll, BrowserMacAgents.scroll)
    static let waitFor = Self(.waitFor, BrowserMacAgents.waitFor)
    static let listConsoleMessages = Self(.listConsoleMessages, BrowserMacAgents.listConsoleMessages)
    static let listNetworkRequests = Self(.listNetworkRequests, BrowserMacAgents.listNetworkRequests)
    static let getNetworkRequest = Self(.getNetworkRequest, BrowserMacAgents.getNetworkRequest)
    static let evaluateScript = Self(.evaluateScript, BrowserMacAgents.evaluateScript)
    static let readPageText = Self(.readPageText, BrowserMacAgents.readPageText)
    static let handleDialog = Self(.handleDialog, BrowserMacAgents.handleDialog)
    static let searchHistory = Self(.searchHistory, BrowserMacAgents.searchHistory)
    static let deleteHistory = Self(.deleteHistory, BrowserMacAgents.deleteHistory)
    static let listSearchProviders = Self(.listSearchProviders, BrowserMacAgents.listSearchProviders)
    static let openWindow = Self(.openWindow, BrowserMacAgents.openWindow)
    static let openBlankWindow = Self(.openBlankWindow, BrowserMacAgents.openBlankWindow)
    static let openQuickWindow = Self(.openQuickWindow, BrowserMacAgents.openQuickWindow)
    static let openPrivateWindow = Self(.openPrivateWindow, BrowserMacAgents.openPrivateWindow)

    static let all: [Self] = [
        identify, listSpaces, listTabs, openTab, navigate, showTab, closeTab, takeSnapshot, screenshot, click, hover,
        fill, typeText, pressKey, scroll, waitFor, listConsoleMessages, listNetworkRequests, getNetworkRequest,
        evaluateScript, readPageText, handleDialog, openPrivateWindow, searchHistory, deleteHistory,
        listSearchProviders, openWindow, openBlankWindow, openQuickWindow,
    ]

    // MARK: - Variables

    let definition: AgentToolDefinition
    /// The service's work for the tool, which it does for a call.
    private let work:
        @MainActor (BrowserMacAgents) -> (BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult

    // MARK: - Initializers

    private init(
        _ definition: AgentToolDefinition,
        _ work:
            @escaping @MainActor (BrowserMacAgents) -> (BrowserAgentCall) async throws(BrowserAgentFailure) ->
            AgentToolResult
    ) {
        self.definition = definition
        self.work = work
    }

    // MARK: - Actions - Calls

    /// The tool an agent names, or nil for one Crest does not have.
    static func named(_ name: String) -> Self? {
        all.first { $0.definition.name == name }
    }

    func perform(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        try await work(call.agents)(call)
    }
}
