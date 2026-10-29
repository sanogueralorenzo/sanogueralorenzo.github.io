import Foundation

enum PaletteActivation: String, CaseIterable, Sendable {
    case switchesToTab, opensAddress, searches, runsCommand, opensSettingsPage, showsSpace, copiesAnswer, entersScope

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var closesPalette: Bool {
        switch self {
        case .switchesToTab: true
        case .opensAddress: true
        case .searches: true
        case .runsCommand: true
        case .opensSettingsPage: true
        case .showsSpace: true
        case .copiesAnswer: true
        case .entersScope: false
        }
    }

    var opensWhereKeysChoose: Bool {
        switch self {
        case .switchesToTab: false
        case .opensAddress: true
        case .searches: true
        case .runsCommand: false
        case .opensSettingsPage: false
        case .showsSpace: false
        case .copiesAnswer: false
        case .entersScope: false
        }
    }
}

enum PaletteReason: String, CaseIterable, Sendable {
    case completion, oftenVisited, recentlyUsed, openTab, kept, titleMatch, addressMatch

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var text: LocalizedStringResource {
        switch self {
        case .completion: LocalizedStringResource("Completes what you typed")
        case .oftenVisited: LocalizedStringResource("Often visited")
        case .recentlyUsed: LocalizedStringResource("Recently used")
        case .openTab: LocalizedStringResource("Already open")
        case .kept: LocalizedStringResource("Pinned or saved")
        case .titleMatch: LocalizedStringResource("Matches the title")
        case .addressMatch: LocalizedStringResource("Matches the address")
        }
    }
}

enum PaletteRowKind: String, CaseIterable, Sendable {
    case openAddress, search, searchSuggestion, tab, pinnedTab, savedTab, folder, command, history, space, settingsPage,
        calculation, scope

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var symbol: String {
        switch self {
        case .openAddress: "globe"
        case .search: "magnifyingglass"
        case .searchSuggestion: "magnifyingglass"
        case .tab: "globe"
        case .pinnedTab: "pin.fill"
        case .savedTab: "bookmark"
        case .folder: "folder"
        case .command: "command"
        case .history: "clock"
        case .space: "square.stack"
        case .settingsPage: "gearshape"
        case .calculation: "equal"
        case .scope: "line.3.horizontal.decrease"
        }
    }

    var action: LocalizedStringResource? {
        switch self {
        case .openAddress: nil
        case .search: nil
        case .searchSuggestion: LocalizedStringResource("Search")
        case .tab: LocalizedStringResource("Switch to Tab")
        case .pinnedTab: LocalizedStringResource("Switch to Tab")
        case .savedTab: LocalizedStringResource("Switch to Tab")
        case .folder: LocalizedStringResource("Open First Tab")
        case .command: nil
        case .history: LocalizedStringResource("Open")
        case .space: LocalizedStringResource("Switch to Space")
        case .settingsPage: LocalizedStringResource("Open Settings")
        case .calculation: LocalizedStringResource("Copy")
        case .scope: LocalizedStringResource("Search")
        }
    }

    var isPrimary: Bool {
        switch self {
        case .openAddress: true
        case .search: true
        case .searchSuggestion: false
        case .tab: false
        case .pinnedTab: false
        case .savedTab: false
        case .folder: false
        case .command: false
        case .history: false
        case .space: false
        case .settingsPage: false
        case .calculation: true
        case .scope: false
        }
    }

    var activation: PaletteActivation {
        switch self {
        case .openAddress: PaletteActivation.opensAddress
        case .search: PaletteActivation.searches
        case .searchSuggestion: PaletteActivation.searches
        case .tab: PaletteActivation.switchesToTab
        case .pinnedTab: PaletteActivation.switchesToTab
        case .savedTab: PaletteActivation.switchesToTab
        case .folder: PaletteActivation.switchesToTab
        case .command: PaletteActivation.runsCommand
        case .history: PaletteActivation.opensAddress
        case .space: PaletteActivation.showsSpace
        case .settingsPage: PaletteActivation.opensSettingsPage
        case .calculation: PaletteActivation.copiesAnswer
        case .scope: PaletteActivation.entersScope
        }
    }

    var forgetsFromHistory: Bool {
        switch self {
        case .openAddress: false
        case .search: false
        case .searchSuggestion: false
        case .tab: false
        case .pinnedTab: false
        case .savedTab: false
        case .folder: false
        case .command: false
        case .history: true
        case .space: false
        case .settingsPage: false
        case .calculation: false
        case .scope: false
        }
    }
}

enum PaletteScope: String, CaseIterable, Sendable {
    case tabs, saved, history, actions, spaces

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var keyword: String {
        switch self {
        case .tabs: "@tabs"
        case .saved: "@saved"
        case .history: "@history"
        case .actions: "@actions"
        case .spaces: "@spaces"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .tabs: LocalizedStringResource("Tabs")
        case .saved: LocalizedStringResource("Pinned & Saved")
        case .history: LocalizedStringResource("History")
        case .actions: LocalizedStringResource("Actions")
        case .spaces: LocalizedStringResource("Spaces")
        }
    }

    var symbol: String {
        switch self {
        case .tabs: "square.on.square"
        case .saved: "pin"
        case .history: "clock"
        case .actions: "command"
        case .spaces: "square.stack"
        }
    }
}

enum PaletteSection: String, CaseIterable, Sendable {
    case intent, searchSuggestions, recentTabs, tabs, actions, saved, history, topHit, spaces

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var title: LocalizedStringResource? {
        switch self {
        case .intent: nil
        case .searchSuggestions: LocalizedStringResource("Search Suggestions")
        case .recentTabs: LocalizedStringResource("Recent Tabs")
        case .tabs: LocalizedStringResource("Tabs")
        case .actions: LocalizedStringResource("Actions")
        case .saved: LocalizedStringResource("Pinned & Saved")
        case .history: LocalizedStringResource("History")
        case .topHit: nil
        case .spaces: LocalizedStringResource("Spaces")
        }
    }

    var limit: Int {
        switch self {
        case .intent: 2
        case .searchSuggestions: 3
        case .recentTabs: 0
        case .tabs: 8
        case .actions: 3
        case .saved: 5
        case .history: 6
        case .topHit: 1
        case .spaces: 2
        }
    }

    var restingLimit: Int {
        switch self {
        case .intent: 1
        case .searchSuggestions: 0
        case .recentTabs: 5
        case .tabs: 0
        case .actions: 3
        case .saved: 0
        case .history: 0
        case .topHit: 0
        case .spaces: 0
        }
    }

    var scopedLimit: Int {
        switch self {
        case .intent: 0
        case .searchSuggestions: 0
        case .recentTabs: 0
        case .tabs: 30
        case .actions: 30
        case .saved: 30
        case .history: 30
        case .topHit: 0
        case .spaces: 30
        }
    }
}
