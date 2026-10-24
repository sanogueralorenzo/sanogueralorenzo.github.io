import AppKit
import Foundation

/// Crest-owned actions placed ahead of an engine's page menu. Engines keep
/// their own editing and extension rows; these actions use Crest's Space and
/// tab routing after the menu closes. Each row carries what it does to the
/// page, given the page's navigation context and the tab it comes from.
struct BrowserPageContextMenuAction {
    // MARK: - Types

    /// Which row this is, with what it does it to.
    enum Kind: Equatable {
        case search
        case peek
        case split
        case space(UUID)
    }

    /// Runs the row on the page, answering whether it did.
    typealias Perform =
        @MainActor (BrowserPage, BrowserPageNavigationContext, BrowserTabRuntimeAssignment) -> Bool

    // MARK: - Variables

    let kind: Kind
    let title: String
    let symbolName: String
    let linkURL: URL?
    let selectionText: String?
    /// The Space a Space destination opens the link in, whose icon its row
    /// shows; nil for every other row.
    var space: BrowserSpaceIdentity?
    let perform: Perform

    var isSpaceDestination: Bool {
        if case .space = kind { return true }
        return false
    }

    // MARK: - Initializers

    init(
        kind: Kind, title: String, symbolName: String, linkURL: URL?, selectionText: String?,
        space: BrowserSpaceIdentity? = nil, perform: @escaping Perform
    ) {
        self.kind = kind
        self.title = title
        self.symbolName = symbolName
        self.linkURL = linkURL
        self.selectionText = selectionText
        self.space = space
        self.perform = perform
    }

    // MARK: - Actions - Rows

    /// Opens `linkURL` in `space`, another Space of the window.
    @MainActor static func space(_ space: SpaceModel, opening linkURL: URL) -> BrowserPageContextMenuAction {
        let id = space.id
        return BrowserPageContextMenuAction(
            kind: .space(id), title: space.settings.name, symbolName: "square.stack.3d.up", linkURL: linkURL,
            selectionText: nil, space: space.identity
        ) { page, _, source in
            guard let space = page.linkDestinationHost.otherSpaces(from: source).first(where: { $0.id == id })
            else { return false }
            return page.linkDestinationHost.openLink(
                linkURL, from: source, in: BrowserSpaceRuntimeAssignment(space: space))
        }
    }

    /// Opens `linkURL` in Peek over the page.
    static func peek(_ linkURL: URL) -> BrowserPageContextMenuAction {
        BrowserPageContextMenuAction(
            kind: .peek, title: String(localized: "Open Link in Peek"), symbolName: "rectangle.on.rectangle",
            linkURL: linkURL, selectionText: nil
        ) { page, context, _ in
            page.openPeek(
                BrowserPeekRequest(
                    url: linkURL, sourceTabID: context.tabID, sourceTitle: context.title,
                    spaceAssignment: context.assignment, trigger: .contextMenu))
            return true
        }
    }

    /// Opens `linkURL` in a split view beside the page's tab.
    static func split(_ linkURL: URL) -> BrowserPageContextMenuAction {
        BrowserPageContextMenuAction(
            kind: .split, title: String(localized: "Open Link in Split View"), symbolName: "rectangle.split.2x1",
            linkURL: linkURL, selectionText: nil
        ) { page, _, _ in
            page.openLinkInSplitView(linkURL)
            return true
        }
    }

    /// Searches for `selectionText` with the engine titled `engineTitle`.
    static func search(_ selectionText: String, with engineTitle: String) -> BrowserPageContextMenuAction {
        BrowserPageContextMenuAction(
            kind: .search, title: String(localized: "Search with \(engineTitle)"), symbolName: "magnifyingglass",
            linkURL: nil, selectionText: selectionText
        ) { page, context, source in
            guard let search = page.linkDestinationHost.selectionSearch(for: selectionText, from: source)
            else { return false }
            return page.linkDestinationHost.openLink(search.url, from: source, in: context.assignment)
        }
    }
}

/// A page that puts Crest's rows in an engine's context menu and runs the one
/// the person picks.
@MainActor
protocol BrowserPageContextMenuHost: AnyObject {
    func contextMenuActions(linkURL: URL?, selectionText: String?) -> [BrowserPageContextMenuAction]
    @discardableResult func performContextMenuAction(_ action: BrowserPageContextMenuAction) -> Bool
}

/// Crest's rows in an engine's context menu for one page: the other Spaces a
/// link opens in grouped under one row, then the page's own rows, ahead of the
/// engine's rows. A row runs only while the page's view is still in the window
/// the menu opened in.
@MainActor
struct BrowserPageContextMenu {
    // MARK: - Types

    /// One row's action, which its menu item keeps and runs.
    @MainActor
    private final class Row: NSObject {
        let action: BrowserPageContextMenuAction
        weak var host: (any BrowserPageContextMenuHost)?
        weak var view: NSView?
        let windowNumber: Int?

        init(_ action: BrowserPageContextMenuAction, host: any BrowserPageContextMenuHost, view: NSView) {
            self.action = action
            self.host = host
            self.view = view
            windowNumber = view.window?.windowNumber
        }

        /// Runs the row on the main queue's next turn, once the engine's menu
        /// and the engine code that showed it have returned, while the page's
        /// view is still in the window the menu opened in.
        ///
        /// The Objective-C name is spelled out: a method named `perform(_:)`
        /// makes `#selector` pick NSObject's `performSelector:`, which sends
        /// the menu item itself as a selector and raises.
        @objc(runContextMenuRow:) func run(_ sender: NSMenuItem) {
            Task { @MainActor in
                guard let view, view.window?.windowNumber == windowNumber else { return }
                host?.performContextMenuAction(action)
            }
        }
    }

    // MARK: - Variables

    let actions: [BrowserPageContextMenuAction]
    let host: any BrowserPageContextMenuHost
    /// The page's view, whose window the menu opened in.
    let view: NSView

    // MARK: - Actions - Menu

    /// Puts the rows ahead of what `menu` holds, with a separator between.
    func insert(into menu: NSMenu) {
        guard !actions.isEmpty else { return }
        var items: [NSMenuItem] = []
        let spaceActions = actions.filter(\.isSpaceDestination)
        if !spaceActions.isEmpty {
            let group = NSMenuItem(
                title: String(localized: "Open Link in Another Space"), action: nil, keyEquivalent: "")
            group.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
            let submenu = NSMenu()
            for action in spaceActions { submenu.addItem(item(for: action)) }
            group.submenu = submenu
            items.append(group)
        }
        items.append(contentsOf: actions.filter { !$0.isSpaceDestination }.map(item(for:)))
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        if menu.items.count > items.count { menu.insertItem(.separator(), at: items.count) }
    }

    private func item(for action: BrowserPageContextMenuAction) -> NSMenuItem {
        let row = Row(action, host: host, view: view)
        let item = NSMenuItem(title: action.title, action: #selector(Row.run(_:)), keyEquivalent: "")
        item.target = row
        // The menu item keeps its row alive.
        item.representedObject = row
        item.image =
            action.space.flatMap { BrowserSpaceSymbolArtworkRenderer.shared.menuImage(for: $0) }
            ?? NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
        return item
    }
}

extension BrowserPage: BrowserPageContextMenuHost {
    func contextMenuActions(linkURL: URL?, selectionText: String?) -> [BrowserPageContextMenuAction] {
        guard let context = navigationContext else { return [] }
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tabID, spaceID: context.spaceID,
            profileID: context.assignment.profileID)
        var actions: [BrowserPageContextMenuAction] = []

        if let linkURL, ExternalWebLink.accepts(linkURL),
            linkDestinationHost.canOpenLink(from: source)
        {
            for space in linkDestinationHost.otherSpaces(from: source) {
                actions.append(.space(space, opening: linkURL))
            }
            actions.append(.peek(linkURL))
            if splitLinkHost.canOpenLink(context.tabID, context.assignment) {
                actions.append(.split(linkURL))
            }
        }
        if let selectionText,
            let search = linkDestinationHost.selectionSearch(for: selectionText, from: source)
        {
            actions.append(.search(selectionText, with: search.engineTitle))
        }
        return actions
    }

    /// Runs a row the menu offered, while the page still offers it for the
    /// same link or selection.
    @discardableResult
    func performContextMenuAction(_ action: BrowserPageContextMenuAction) -> Bool {
        guard
            contextMenuActions(linkURL: action.linkURL, selectionText: action.selectionText)
                .contains(where: { $0.kind == action.kind }),
            let context = navigationContext
        else { return false }
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tabID, spaceID: context.spaceID,
            profileID: context.assignment.profileID)
        return action.perform(self, context, source)
    }
}
