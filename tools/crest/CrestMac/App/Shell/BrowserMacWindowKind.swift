import AppKit
import SwiftUI

/// A kind of window the shell opens: how it looks, the size it opens at,
/// where it is placed, whether it keeps its frame, and what it holds. Every
/// shell window opens through one kind, so a new kind of window is one more
/// instance.
@MainActor
struct BrowserMacWindowKind: Hashable {
    // MARK: - Static Variables

    /// The style of every window that shows pages.
    private static let browsingStyle: NSWindow.StyleMask = [
        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
    ]
    /// The size a browser window opens at, and the smallest its content may be.
    static let browserContentSize = CGSize(width: 1440, height: 900)
    static let browserMinimumContentSize = CGSize(width: 900, height: 600)

    /// A browser window over the person's own Spaces, which keeps its frame
    /// under its identity and cascades from the window the person is using.
    static let browser = BrowserMacWindowKind(
        name: "browser", title: ProductIdentity.name, styleMask: browsingStyle, hidesTitle: true,
        contentSize: browserContentSize,
        minimumContentSize: browserMinimumContentSize,
        savesFrame: true, hasWindowModel: true, hasPageRow: true)
    /// A browser window over a torn-off tab's own workspace, placed where the
    /// tab was dropped and never kept.
    static let temporary = BrowserMacWindowKind(
        name: "temporary", title: ProductIdentity.name, styleMask: browsingStyle, hidesTitle: true,
        contentSize: browserContentSize,
        minimumContentSize: browserMinimumContentSize,
        hasWindowModel: true, hasPageRow: true)
    /// The one private browsing window.
    static let `private` = BrowserMacWindowKind(
        name: "private", title: String(localized: "Private Browsing"), styleMask: browsingStyle, hidesTitle: true,
        contentSize: CGSize(width: 1200, height: 820), hasPageRow: true, isSingleton: true)
    /// A Quick Window, which shows one page of a Space.
    static let quick = BrowserMacWindowKind(
        name: "quick", title: String(localized: "Quick Window"), styleMask: browsingStyle, hidesTitle: true,
        contentSize: CGSize(
            width: BrowserQuickWindowLayout.defaultWidth, height: BrowserQuickWindowLayout.defaultHeight),
        minimumContentSize: CGSize(
            width: BrowserQuickWindowLayout.minimumWidth, height: BrowserQuickWindowLayout.minimumHeight))
    /// Crest Setup, which fills the screen it opens on. The setup content is
    /// fully flexible above its minimum, so the window keeps the size it opens
    /// at rather than the content's ideal one, which is that minimum.
    static let setup = BrowserMacWindowKind(
        name: "setup", title: BrowserOnboardingWindowActivation.windowTitle,
        styleMask: [.titled, .closable, .resizable, .fullSizeContentView], hidesTitle: true,
        hidesTitleBarSeparator: true, contentSize: CGSize(width: 1440, height: 900),
        minimumContentSize: CGSize(width: 980, height: 660),
        sizingOptions: [], fillsScreen: true, isSingleton: true, identifier: "onboarding")
    /// The release notes for the update the sidebar card presents, which keep
    /// their content's minimum size.
    static let updateDetails = BrowserMacWindowKind(
        name: "update-details", title: String(localized: "What's New in Crest"),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        contentSize: CGSize(width: 620, height: 520), sizingOptions: [.minSize], isSingleton: true,
        identifier: "software-update-details")
    static let all: [BrowserMacWindowKind] = [browser, temporary, `private`, quick, setup, updateDetails]

    // MARK: - Variables

    /// The kind's name, which identifies it.
    nonisolated let name: String
    /// The window's title, which the window list and accessibility read even
    /// when the title bar hides it.
    let title: String
    let styleMask: NSWindow.StyleMask
    /// Whether the content draws under a transparent title bar that shows no
    /// title.
    let hidesTitle: Bool
    /// Whether the title bar draws no separator above the content.
    let hidesTitleBarSeparator: Bool
    /// The content size the window opens at when it keeps no frame of its own.
    let contentSize: CGSize
    let minimumContentSize: CGSize?
    /// How the hosted content sizes the window, or nil for the hosting
    /// controller's own default.
    let sizingOptions: NSHostingSizingOptions?
    /// Whether the window keeps its frame under its identity for the next time
    /// it opens; any other window opens centered.
    let savesFrame: Bool
    /// Whether the window opens filling the visible screen, as a stage does,
    /// rather than at its content size.
    let fillsScreen: Bool
    /// Whether the window coordinator models the window: a browser window over
    /// a workspace of the person's own Spaces.
    let hasWindowModel: Bool
    /// Whether the window shows a page row, which can hold an extension's side
    /// panel beside a page.
    let hasPageRow: Bool
    /// Whether one window of the kind is open at a time, which is brought
    /// forward when asked for again.
    let isSingleton: Bool
    /// The window's fixed identifier, or nil when it is identified by the
    /// window's own identity in the core.
    let identifier: String?

    // MARK: - Initializers

    private init(
        name: String, title: String, styleMask: NSWindow.StyleMask, hidesTitle: Bool = false,
        hidesTitleBarSeparator: Bool = false, contentSize: CGSize, minimumContentSize: CGSize? = nil,
        sizingOptions: NSHostingSizingOptions? = nil,
        savesFrame: Bool = false, fillsScreen: Bool = false, hasWindowModel: Bool = false, hasPageRow: Bool = false,
        isSingleton: Bool = false, identifier: String? = nil
    ) {
        self.name = name
        self.title = title
        self.styleMask = styleMask
        self.hidesTitle = hidesTitle
        self.hidesTitleBarSeparator = hidesTitleBarSeparator
        self.contentSize = contentSize
        self.minimumContentSize = minimumContentSize
        self.sizingOptions = sizingOptions
        self.savesFrame = savesFrame
        self.fillsScreen = fillsScreen
        self.hasWindowModel = hasWindowModel
        self.hasPageRow = hasPageRow
        self.isSingleton = isSingleton
        self.identifier = identifier
    }

    // MARK: - Actions - Windows

    /// The kind of the browser window `request` opens.
    static func browsing(_ request: BrowserMacWindowRequest) -> BrowserMacWindowKind {
        request.kind == .temporary ? temporary : browser
    }

    /// A new window of this kind, identified by `windowID` unless the kind has
    /// a fixed identifier, which the shell keeps and closes itself.
    func makeWindow(identifiedBy windowID: UUID) -> BrowserMacWindow {
        let window = BrowserMacWindow(
            contentRect: NSRect(origin: .zero, size: contentSize), styleMask: styleMask, backing: .buffered,
            defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(identifier ?? windowID.uuidString)
        window.title = title
        window.isReleasedWhenClosed = false
        // The core decides which windows a launch reopens; AppKit restores
        // none of its own.
        window.isRestorable = false
        window.tabbingMode = .disallowed
        if let minimumContentSize { window.contentMinSize = minimumContentSize }
        if hidesTitle {
            // Set before the first layout, so the content never lays itself
            // out under an opaque title bar.
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
        if hidesTitleBarSeparator { window.titlebarSeparatorStyle = .none }
        return window
    }

    /// Hosts `content` in `window` and opens it at this kind's size. A hosting
    /// controller sizes its window to content SwiftUI has not laid out yet,
    /// which would leave a new window at its minimum size.
    func host(_ content: some View, in window: NSWindow) {
        let controller = NSHostingController(rootView: content)
        if let sizingOptions { controller.sizingOptions = sizingOptions }
        window.contentViewController = controller
        window.setContentSize(contentSize)
    }
}

// MARK: - Hashable

extension BrowserMacWindowKind {
    nonisolated static func == (lhs: BrowserMacWindowKind, rhs: BrowserMacWindowKind) -> Bool {
        lhs.name == rhs.name
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
