import Foundation

/// Crest’s fixed command catalog, shared by menus, keys and the palette.
struct ShortcutCommand: Hashable, Sendable {
    enum Kinds: Sendable {
        case newWindow
        case newBlankWindow
        case newTab
        case newPrivateWindow
        case closeTabOrWindow
        case closeWindow
        case openLocation
        case back
        case forward
        case reloadPage
        case stopLoading
        case reloadFromOrigin
        case toggleSelectedTabPinned
        case duplicateTab
        case reopenClosedTab
        case clearUnpinnedTabs
        case archiveTab
        case previousTab
        case nextTab
        case mostRecentTab
        case mostRecentTabBackward
        case selectNumbered
        case previousSpace
        case nextSpace
        case toggleReaderMode
        case toggleContentBlocking
        case findInPage
        case zoomIn
        case zoomOut
        case actualSize
        case copyPageLink
        case copyPageLinkAsMarkdown
        case sharePage
        case exportPDF
        case saveWebArchive
        case printPage
        case toggleSidebar
        case showHistory
        case showArchive
        case showDownloads
        case showWebInspector
        case splitWithNextTab
        case focusNextSplitCard
        case focusPreviousSplitCard
        case removeTabFromSplit
        case separateSplitTabs
        case moveSplitCardLeft
        case moveSplitCardRight
        case toggleDeveloperToolbar
        case translatePage
        case openFile
        case findNext
        case findPrevious
    }

    let kind: Kinds
    let name: String
    let section: ShortcutSection
    let title: LocalizedStringResource
    let searchTerms: LocalizedStringResource?
    let menuTitle: LocalizedStringResource?
    let symbol: String
    let requiredCapability: EngineCapability?
    let selects: NumberedSelectionTarget?
    let number: Int?
    let defaultShortcuts: [ShortcutDefault]
    let paletteRest: Int?
    let offersInPalette: Bool
    let isReservedFromPages: Bool
    let availability: ShortcutAvailability

    private init(
        kind: Kinds,
        name: String,
        section: ShortcutSection,
        title: LocalizedStringResource,
        searchTerms: LocalizedStringResource? = nil,
        menuTitle: LocalizedStringResource? = nil,
        symbol: String,
        requiredCapability: EngineCapability? = nil,
        selects: NumberedSelectionTarget? = nil,
        number: Int? = nil,
        defaultShortcuts: [ShortcutDefault] = [],
        paletteRest: Int? = nil,
        offersInPalette: Bool = true,
        isReservedFromPages: Bool = false,
        availability: ShortcutAvailability = .always
    ) {
        self.kind = kind
        self.name = name
        self.section = section
        self.title = title
        self.searchTerms = searchTerms
        self.menuTitle = menuTitle
        self.symbol = symbol
        self.requiredCapability = requiredCapability
        self.selects = selects
        self.number = number
        self.defaultShortcuts = defaultShortcuts
        self.paletteRest = paletteRest
        self.offersInPalette = offersInPalette
        self.isReservedFromPages = isReservedFromPages
        self.availability = availability
    }

    static let newWindow = ShortcutCommand(
        kind: .newWindow, name: "newWindow", section: ShortcutSection.everyday,
        title: LocalizedStringResource("New Window"), symbol: "macwindow.badge.plus",
        defaultShortcuts: everywhere(KeyCombination(key: "n", isSpecialKey: false, modifiers: [.command])),
        paletteRest: 1, isReservedFromPages: true)
    static let newBlankWindow = ShortcutCommand(
        kind: .newBlankWindow, name: "newBlankWindow", section: ShortcutSection.everyday,
        title: LocalizedStringResource("New Blank Window"),
        searchTerms: LocalizedStringResource("temporary disposable unsynced window"), symbol: "macwindow.badge.plus",
        defaultShortcuts: [
            ShortcutDefault(
                platform: DevicePlatform.desktop,
                keys: KeyCombination(key: "n", isSpecialKey: false, modifiers: [.command, .option])
            )
        ], availability: .normalSpace)
    static let newTab = ShortcutCommand(
        kind: .newTab, name: "newTab", section: ShortcutSection.everyday, title: LocalizedStringResource("New Tab"),
        symbol: "plus.square",
        defaultShortcuts: everywhere(KeyCombination(key: "t", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false, isReservedFromPages: true)
    static let newPrivateWindow = ShortcutCommand(
        kind: .newPrivateWindow, name: "newPrivateWindow", section: ShortcutSection.everyday,
        title: LocalizedStringResource("New Private Window"),
        searchTerms: LocalizedStringResource("incognito private browsing"), symbol: "eyeglasses",
        defaultShortcuts: everywhere(KeyCombination(key: "n", isSpecialKey: false, modifiers: [.command, .shift])),
        isReservedFromPages: true)
    static let closeTabOrWindow = ShortcutCommand(
        kind: .closeTabOrWindow, name: "closeTabOrWindow", section: ShortcutSection.everyday,
        title: LocalizedStringResource("Close Current Tab or Window"),
        searchTerms: LocalizedStringResource("close archive current tab window"), symbol: "xmark.square",
        defaultShortcuts: everywhere(KeyCombination(key: "w", isSpecialKey: false, modifiers: [.command])),
        isReservedFromPages: true)
    static let closeWindow = ShortcutCommand(
        kind: .closeWindow, name: "closeWindow", section: ShortcutSection.everyday,
        title: LocalizedStringResource("Close Window"), symbol: "xmark.square",
        defaultShortcuts: everywhere(KeyCombination(key: "w", isSpecialKey: false, modifiers: [.command, .shift])),
        isReservedFromPages: true)
    static let openLocation = ShortcutCommand(
        kind: .openLocation, name: "openLocation", section: ShortcutSection.everyday,
        title: LocalizedStringResource("Open Location"),
        searchTerms: LocalizedStringResource("change current tab url address focus"), symbol: "magnifyingglass",
        defaultShortcuts: everywhere(KeyCombination(key: "l", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false)
    static let back = ShortcutCommand(
        kind: .back, name: "back", section: ShortcutSection.everyday, title: LocalizedStringResource("Back"),
        symbol: "chevron.left",
        defaultShortcuts: everywhere(KeyCombination(key: "[", isSpecialKey: false, modifiers: [.command])))
    static let forward = ShortcutCommand(
        kind: .forward, name: "forward", section: ShortcutSection.everyday, title: LocalizedStringResource("Forward"),
        symbol: "chevron.right",
        defaultShortcuts: everywhere(KeyCombination(key: "]", isSpecialKey: false, modifiers: [.command])))
    static let reloadPage = ShortcutCommand(
        kind: .reloadPage, name: "reloadPage", section: ShortcutSection.everyday,
        title: LocalizedStringResource("Reload Page"), symbol: "arrow.clockwise",
        defaultShortcuts: everywhere(KeyCombination(key: "r", isSpecialKey: false, modifiers: [.command])),
        availability: .webPage)
    static let stopLoading = ShortcutCommand(
        kind: .stopLoading, name: "stopLoading", section: ShortcutSection.everyday,
        title: LocalizedStringResource("Stop Loading"), symbol: "xmark.circle",
        defaultShortcuts: everywhere(KeyCombination(key: ".", isSpecialKey: false, modifiers: [.command])))
    static let reloadFromOrigin = ShortcutCommand(
        kind: .reloadFromOrigin, name: "reloadFromOrigin", section: ShortcutSection.everyday,
        title: LocalizedStringResource("Reload from Origin"), symbol: "arrow.clockwise",
        defaultShortcuts: everywhere(KeyCombination(key: "r", isSpecialKey: false, modifiers: [.command, .shift])),
        availability: .webPage)
    static let toggleSelectedTabPinned = ShortcutCommand(
        kind: .toggleSelectedTabPinned, name: "toggleSelectedTabPinned", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Pin or Unpin Current Tab"),
        searchTerms: LocalizedStringResource("favorite bookmark pin unpin"),
        menuTitle: LocalizedStringResource("Pin or Unpin Tab"), symbol: "pin",
        defaultShortcuts: everywhere(KeyCombination(key: "d", isSpecialKey: false, modifiers: [.command])),
        availability: .tab)
    static let duplicateTab = ShortcutCommand(
        kind: .duplicateTab, name: "duplicateTab", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Duplicate Tab"), symbol: "plus.square.on.square", availability: .nonStartTab)
    static let reopenClosedTab = ShortcutCommand(
        kind: .reopenClosedTab, name: "reopenClosedTab", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Reopen Last Closed Tab"),
        menuTitle: LocalizedStringResource("Reopen Closed Tab"), symbol: "arrow.uturn.backward",
        defaultShortcuts: everywhere(KeyCombination(key: "t", isSpecialKey: false, modifiers: [.command, .shift])),
        paletteRest: 2, isReservedFromPages: true, availability: .archive)
    static let clearUnpinnedTabs = ShortcutCommand(
        kind: .clearUnpinnedTabs, name: "clearUnpinnedTabs", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Clear Current Tabs"),
        searchTerms: LocalizedStringResource("clean tidy archive unpinned tabs"), symbol: "sparkles",
        defaultShortcuts: everywhere(KeyCombination(key: "k", isSpecialKey: false, modifiers: [.command, .shift])))
    static let archiveTab = ShortcutCommand(
        kind: .archiveTab, name: "archiveTab", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Archive Tab"), symbol: "archivebox",
        defaultShortcuts: everywhere(KeyCombination(key: "e", isSpecialKey: false, modifiers: [.command])),
        availability: .currentTab)
    static let previousTab = ShortcutCommand(
        kind: .previousTab, name: "previousTab", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Previous Tab"),
        searchTerms: LocalizedStringResource("switch cycle tabs up down arrow"), symbol: "chevron.up",
        defaultShortcuts: everywhere(
            KeyCombination(key: "upArrow", isSpecialKey: true, modifiers: [.command, .option])),
        isReservedFromPages: true)
    static let nextTab = ShortcutCommand(
        kind: .nextTab, name: "nextTab", section: ShortcutSection.tabs, title: LocalizedStringResource("Next Tab"),
        searchTerms: LocalizedStringResource("switch cycle tabs up down arrow"), symbol: "chevron.down",
        defaultShortcuts: everywhere(
            KeyCombination(key: "downArrow", isSpecialKey: true, modifiers: [.command, .option])),
        isReservedFromPages: true)
    static let mostRecentTab = ShortcutCommand(
        kind: .mostRecentTab, name: "mostRecentTab", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Most Recent Tab"),
        searchTerms: LocalizedStringResource("toggle recent switch tabs"), symbol: "arrow.left.arrow.right",
        defaultShortcuts: everywhere(KeyCombination(key: "tab", isSpecialKey: true, modifiers: [.control])),
        isReservedFromPages: true)
    static let mostRecentTabBackward = ShortcutCommand(
        kind: .mostRecentTabBackward, name: "mostRecentTabBackward", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Most Recent Tab Backward"),
        searchTerms: LocalizedStringResource("toggle recent switch tabs oldest back"), symbol: "arrow.left.arrow.right",
        defaultShortcuts: everywhere(KeyCombination(key: "tab", isSpecialKey: true, modifiers: [.control, .shift])),
        isReservedFromPages: true)
    static let selectTab1 = ShortcutCommand(
        kind: .selectNumbered, name: "selectTab1", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Select Tab \(1)"), symbol: "square.on.square",
        selects: NumberedSelectionTarget.tab, number: 1,
        defaultShortcuts: everywhere(KeyCombination(key: "1", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false)
    static let selectTab2 = ShortcutCommand(
        kind: .selectNumbered, name: "selectTab2", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Select Tab \(2)"), symbol: "square.on.square",
        selects: NumberedSelectionTarget.tab, number: 2,
        defaultShortcuts: everywhere(KeyCombination(key: "2", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false)
    static let selectTab3 = ShortcutCommand(
        kind: .selectNumbered, name: "selectTab3", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Select Tab \(3)"), symbol: "square.on.square",
        selects: NumberedSelectionTarget.tab, number: 3,
        defaultShortcuts: everywhere(KeyCombination(key: "3", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false)
    static let selectTab4 = ShortcutCommand(
        kind: .selectNumbered, name: "selectTab4", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Select Tab \(4)"), symbol: "square.on.square",
        selects: NumberedSelectionTarget.tab, number: 4,
        defaultShortcuts: everywhere(KeyCombination(key: "4", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false)
    static let selectTab5 = ShortcutCommand(
        kind: .selectNumbered, name: "selectTab5", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Select Tab \(5)"), symbol: "square.on.square",
        selects: NumberedSelectionTarget.tab, number: 5,
        defaultShortcuts: everywhere(KeyCombination(key: "5", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false)
    static let selectTab6 = ShortcutCommand(
        kind: .selectNumbered, name: "selectTab6", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Select Tab \(6)"), symbol: "square.on.square",
        selects: NumberedSelectionTarget.tab, number: 6,
        defaultShortcuts: everywhere(KeyCombination(key: "6", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false)
    static let selectTab7 = ShortcutCommand(
        kind: .selectNumbered, name: "selectTab7", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Select Tab \(7)"), symbol: "square.on.square",
        selects: NumberedSelectionTarget.tab, number: 7,
        defaultShortcuts: everywhere(KeyCombination(key: "7", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false)
    static let selectTab8 = ShortcutCommand(
        kind: .selectNumbered, name: "selectTab8", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Select Tab \(8)"), symbol: "square.on.square",
        selects: NumberedSelectionTarget.tab, number: 8,
        defaultShortcuts: everywhere(KeyCombination(key: "8", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false)
    static let selectTab9 = ShortcutCommand(
        kind: .selectNumbered, name: "selectTab9", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Select Tab \(9)"), symbol: "square.on.square",
        selects: NumberedSelectionTarget.tab, number: 9,
        defaultShortcuts: everywhere(KeyCombination(key: "9", isSpecialKey: false, modifiers: [.command])),
        offersInPalette: false)
    static let previousSpace = ShortcutCommand(
        kind: .previousSpace, name: "previousSpace", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Previous Space"),
        searchTerms: LocalizedStringResource("switch cycle spaces left right arrow"), symbol: "chevron.up",
        defaultShortcuts: everywhere(
            KeyCombination(key: "leftArrow", isSpecialKey: true, modifiers: [.command, .option])))
    static let nextSpace = ShortcutCommand(
        kind: .nextSpace, name: "nextSpace", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Next Space"),
        searchTerms: LocalizedStringResource("switch cycle spaces left right arrow"), symbol: "chevron.down",
        defaultShortcuts: everywhere(
            KeyCombination(key: "rightArrow", isSpecialKey: true, modifiers: [.command, .option])))
    static let selectSpace1 = ShortcutCommand(
        kind: .selectNumbered, name: "selectSpace1", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Select Space \(1)"), symbol: "rectangle.3.group",
        selects: NumberedSelectionTarget.space, number: 1,
        defaultShortcuts: everywhere(KeyCombination(key: "1", isSpecialKey: false, modifiers: [.control])),
        offersInPalette: false)
    static let selectSpace2 = ShortcutCommand(
        kind: .selectNumbered, name: "selectSpace2", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Select Space \(2)"), symbol: "rectangle.3.group",
        selects: NumberedSelectionTarget.space, number: 2,
        defaultShortcuts: everywhere(KeyCombination(key: "2", isSpecialKey: false, modifiers: [.control])),
        offersInPalette: false)
    static let selectSpace3 = ShortcutCommand(
        kind: .selectNumbered, name: "selectSpace3", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Select Space \(3)"), symbol: "rectangle.3.group",
        selects: NumberedSelectionTarget.space, number: 3,
        defaultShortcuts: everywhere(KeyCombination(key: "3", isSpecialKey: false, modifiers: [.control])),
        offersInPalette: false)
    static let selectSpace4 = ShortcutCommand(
        kind: .selectNumbered, name: "selectSpace4", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Select Space \(4)"), symbol: "rectangle.3.group",
        selects: NumberedSelectionTarget.space, number: 4,
        defaultShortcuts: everywhere(KeyCombination(key: "4", isSpecialKey: false, modifiers: [.control])),
        offersInPalette: false)
    static let selectSpace5 = ShortcutCommand(
        kind: .selectNumbered, name: "selectSpace5", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Select Space \(5)"), symbol: "rectangle.3.group",
        selects: NumberedSelectionTarget.space, number: 5,
        defaultShortcuts: everywhere(KeyCombination(key: "5", isSpecialKey: false, modifiers: [.control])),
        offersInPalette: false)
    static let selectSpace6 = ShortcutCommand(
        kind: .selectNumbered, name: "selectSpace6", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Select Space \(6)"), symbol: "rectangle.3.group",
        selects: NumberedSelectionTarget.space, number: 6,
        defaultShortcuts: everywhere(KeyCombination(key: "6", isSpecialKey: false, modifiers: [.control])),
        offersInPalette: false)
    static let selectSpace7 = ShortcutCommand(
        kind: .selectNumbered, name: "selectSpace7", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Select Space \(7)"), symbol: "rectangle.3.group",
        selects: NumberedSelectionTarget.space, number: 7,
        defaultShortcuts: everywhere(KeyCombination(key: "7", isSpecialKey: false, modifiers: [.control])),
        offersInPalette: false)
    static let selectSpace8 = ShortcutCommand(
        kind: .selectNumbered, name: "selectSpace8", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Select Space \(8)"), symbol: "rectangle.3.group",
        selects: NumberedSelectionTarget.space, number: 8,
        defaultShortcuts: everywhere(KeyCombination(key: "8", isSpecialKey: false, modifiers: [.control])),
        offersInPalette: false)
    static let selectSpace9 = ShortcutCommand(
        kind: .selectNumbered, name: "selectSpace9", section: ShortcutSection.spaces,
        title: LocalizedStringResource("Select Space \(9)"), symbol: "rectangle.3.group",
        selects: NumberedSelectionTarget.space, number: 9,
        defaultShortcuts: everywhere(KeyCombination(key: "9", isSpecialKey: false, modifiers: [.control])),
        offersInPalette: false)
    static let toggleReaderMode = ShortcutCommand(
        kind: .toggleReaderMode, name: "toggleReaderMode", section: ShortcutSection.page,
        title: LocalizedStringResource("Show or Hide Reader"),
        searchTerms: LocalizedStringResource("reader reading mode"), symbol: "doc.plaintext",
        requiredCapability: EngineCapability.reader)
    static let toggleContentBlocking = ShortcutCommand(
        kind: .toggleContentBlocking, name: "toggleContentBlocking", section: ShortcutSection.page,
        title: LocalizedStringResource("Toggle Content Blocking"),
        searchTerms: LocalizedStringResource("ads trackers privacy protection"), symbol: "shield",
        requiredCapability: EngineCapability.contentBlocking, availability: .space)
    static let findInPage = ShortcutCommand(
        kind: .findInPage, name: "findInPage", section: ShortcutSection.page,
        title: LocalizedStringResource("Find in Page"), symbol: "text.magnifyingglass",
        defaultShortcuts: everywhere(KeyCombination(key: "f", isSpecialKey: false, modifiers: [.command])))
    static let zoomIn = ShortcutCommand(
        kind: .zoomIn, name: "zoomIn", section: ShortcutSection.page, title: LocalizedStringResource("Zoom In"),
        symbol: "plus.magnifyingglass",
        defaultShortcuts: everywhere(KeyCombination(key: "+", isSpecialKey: false, modifiers: [.command])))
    static let zoomOut = ShortcutCommand(
        kind: .zoomOut, name: "zoomOut", section: ShortcutSection.page, title: LocalizedStringResource("Zoom Out"),
        symbol: "minus.magnifyingglass",
        defaultShortcuts: everywhere(KeyCombination(key: "-", isSpecialKey: false, modifiers: [.command])))
    static let actualSize = ShortcutCommand(
        kind: .actualSize, name: "actualSize", section: ShortcutSection.page,
        title: LocalizedStringResource("Actual Size"), searchTerms: LocalizedStringResource("reset zoom zero"),
        symbol: "1.magnifyingglass",
        defaultShortcuts: everywhere(KeyCombination(key: "0", isSpecialKey: false, modifiers: [.command])))
    static let copyPageLink = ShortcutCommand(
        kind: .copyPageLink, name: "copyPageLink", section: ShortcutSection.page,
        title: LocalizedStringResource("Copy Page Link"),
        searchTerms: LocalizedStringResource("copy url address clipboard"), symbol: "link",
        defaultShortcuts: everywhere(KeyCombination(key: "c", isSpecialKey: false, modifiers: [.command, .shift])))
    static let copyPageLinkAsMarkdown = ShortcutCommand(
        kind: .copyPageLinkAsMarkdown, name: "copyPageLinkAsMarkdown", section: ShortcutSection.page,
        title: LocalizedStringResource("Copy Page Link as Markdown"),
        searchTerms: LocalizedStringResource("copy url address markdown clipboard"), symbol: "link",
        defaultShortcuts: everywhere(
            KeyCombination(key: "c", isSpecialKey: false, modifiers: [.command, .option, .shift])))
    static let sharePage = ShortcutCommand(
        kind: .sharePage, name: "sharePage", section: ShortcutSection.page,
        title: LocalizedStringResource("Share Page"), menuTitle: LocalizedStringResource("Share…"),
        symbol: "square.and.arrow.up")
    static let exportPDF = ShortcutCommand(
        kind: .exportPDF, name: "exportPDF", section: ShortcutSection.page,
        title: LocalizedStringResource("Export as PDF"), menuTitle: LocalizedStringResource("Export as PDF…"),
        symbol: "square.and.arrow.down")
    static let saveWebArchive = ShortcutCommand(
        kind: .saveWebArchive, name: "saveWebArchive", section: ShortcutSection.page,
        title: LocalizedStringResource("Save Web Archive"), menuTitle: LocalizedStringResource("Save Web Archive…"),
        symbol: "square.and.arrow.down")
    static let printPage = ShortcutCommand(
        kind: .printPage, name: "printPage", section: ShortcutSection.page,
        title: LocalizedStringResource("Print Page"), menuTitle: LocalizedStringResource("Print…"), symbol: "printer",
        defaultShortcuts: everywhere(KeyCombination(key: "p", isSpecialKey: false, modifiers: [.command])))
    static let toggleSidebar = ShortcutCommand(
        kind: .toggleSidebar, name: "toggleSidebar", section: ShortcutSection.view,
        title: LocalizedStringResource("Show or Hide Sidebar"), menuTitle: LocalizedStringResource("Toggle Sidebar"),
        symbol: "sidebar.leading",
        defaultShortcuts: [
            ShortcutDefault(
                platform: DevicePlatform.mobile,
                keys: KeyCombination(key: "b", isSpecialKey: false, modifiers: [.command])
            )
        ])
    static let showHistory = ShortcutCommand(
        kind: .showHistory, name: "showHistory", section: ShortcutSection.view,
        title: LocalizedStringResource("Show History"), searchTerms: LocalizedStringResource("visited pages history"),
        symbol: "clock",
        defaultShortcuts: everywhere(KeyCombination(key: "y", isSpecialKey: false, modifiers: [.command])),
        paletteRest: 3)
    static let showArchive = ShortcutCommand(
        kind: .showArchive, name: "showArchive", section: ShortcutSection.view,
        title: LocalizedStringResource("Show Archive"), searchTerms: LocalizedStringResource("closed tabs archive"),
        symbol: "archivebox", availability: .space)
    static let showDownloads = ShortcutCommand(
        kind: .showDownloads, name: "showDownloads", section: ShortcutSection.view,
        title: LocalizedStringResource("Show Downloads"),
        searchTerms: LocalizedStringResource("download files transfers"), symbol: "arrow.down.circle",
        defaultShortcuts: everywhere(KeyCombination(key: "j", isSpecialKey: false, modifiers: [.command, .shift])),
        paletteRest: 4)
    static let showWebInspector = ShortcutCommand(
        kind: .showWebInspector, name: "webInspectorInstructions", section: ShortcutSection.view,
        title: LocalizedStringResource("Show Web Inspector"),
        searchTerms: LocalizedStringResource("developer tools inspect element webkit safari"), symbol: "hammer",
        defaultShortcuts: everywhere(KeyCombination(key: "i", isSpecialKey: false, modifiers: [.command, .option])))
    static let splitWithNextTab = ShortcutCommand(
        kind: .splitWithNextTab, name: "splitWithNextTab", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Split With Next Tab"),
        searchTerms: LocalizedStringResource("split view cards side by side columns"), symbol: "rectangle.split.2x1",
        availability: .splitCandidate)
    static let focusNextSplitCard = ShortcutCommand(
        kind: .focusNextSplitCard, name: "focusNextSplitCard", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Focus Next Split Card"),
        searchTerms: LocalizedStringResource("split view cards focus cycle left right arrow"),
        symbol: "rectangle.righthalf.filled",
        defaultShortcuts: everywhere(
            KeyCombination(key: "rightArrow", isSpecialKey: true, modifiers: [.command, .control])),
        availability: .split)
    static let focusPreviousSplitCard = ShortcutCommand(
        kind: .focusPreviousSplitCard, name: "focusPreviousSplitCard", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Focus Previous Split Card"),
        searchTerms: LocalizedStringResource("split view cards focus cycle left right arrow"),
        symbol: "rectangle.lefthalf.filled",
        defaultShortcuts: everywhere(
            KeyCombination(key: "leftArrow", isSpecialKey: true, modifiers: [.command, .control])), availability: .split
    )
    static let removeTabFromSplit = ShortcutCommand(
        kind: .removeTabFromSplit, name: "removeTabFromSplit", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Remove Tab From Split"),
        searchTerms: LocalizedStringResource("split view card remove leave unsplit"), symbol: "minus.rectangle",
        availability: .split)
    static let separateSplitTabs = ShortcutCommand(
        kind: .separateSplitTabs, name: "separateSplitTabs", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Separate All Tabs"),
        searchTerms: LocalizedStringResource("split view break up unsplit separate cards"),
        symbol: "rectangle.split.2x1.slash",
        defaultShortcuts: everywhere(KeyCombination(key: "u", isSpecialKey: false, modifiers: [.command, .option])),
        availability: .split)
    static let moveSplitCardLeft = ShortcutCommand(
        kind: .moveSplitCardLeft, name: "moveSplitCardLeft", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Move Split Card Left"),
        searchTerms: LocalizedStringResource("split view cards move reorder rearrange left right arrow"),
        symbol: "arrow.left.square",
        defaultShortcuts: everywhere(
            KeyCombination(key: "leftArrow", isSpecialKey: true, modifiers: [.command, .shift])), availability: .split)
    static let moveSplitCardRight = ShortcutCommand(
        kind: .moveSplitCardRight, name: "moveSplitCardRight", section: ShortcutSection.tabs,
        title: LocalizedStringResource("Move Split Card Right"),
        searchTerms: LocalizedStringResource("split view cards move reorder rearrange left right arrow"),
        symbol: "arrow.right.square",
        defaultShortcuts: everywhere(
            KeyCombination(key: "rightArrow", isSpecialKey: true, modifiers: [.command, .shift])), availability: .split)
    static let toggleDeveloperToolbar = ShortcutCommand(
        kind: .toggleDeveloperToolbar, name: "toggleDeveloperToolbar", section: ShortcutSection.view,
        title: LocalizedStringResource("Show or Hide Developer Toolbar"),
        searchTerms: LocalizedStringResource("developer toolbar viewport preview responsive custom size"),
        menuTitle: LocalizedStringResource("Show Developer Toolbar"), symbol: "macbook.and.iphone",
        defaultShortcuts: everywhere(KeyCombination(key: "i", isSpecialKey: false, modifiers: [.command, .shift])))
    static let translatePage = ShortcutCommand(
        kind: .translatePage, name: "translatePage", section: ShortcutSection.view,
        title: LocalizedStringResource("Translate Page"),
        searchTerms: LocalizedStringResource("translate translation language"),
        menuTitle: LocalizedStringResource("Translate Page"), symbol: "translate",
        requiredCapability: EngineCapability.translation,
        defaultShortcuts: everywhere(KeyCombination(key: "l", isSpecialKey: false, modifiers: [.command, .shift])))
    static let openFile = ShortcutCommand(
        kind: .openFile, name: "openFile", section: ShortcutSection.everyday,
        title: LocalizedStringResource("Open File"),
        searchTerms: LocalizedStringResource("open local file document html pdf archive webarchive mhtml"),
        menuTitle: LocalizedStringResource("Open File…"), symbol: "folder", availability: .space)
    static let findNext = ShortcutCommand(
        kind: .findNext, name: "findNext", section: ShortcutSection.page, title: LocalizedStringResource("Find Next"),
        searchTerms: LocalizedStringResource("next match search again"), symbol: "chevron.down",
        defaultShortcuts: [
            ShortcutDefault(
                platform: DevicePlatform.desktop,
                keys: KeyCombination(key: "g", isSpecialKey: false, modifiers: [.command])
            )
        ], availability: .webPage)
    static let findPrevious = ShortcutCommand(
        kind: .findPrevious, name: "findPrevious", section: ShortcutSection.page,
        title: LocalizedStringResource("Find Previous"),
        searchTerms: LocalizedStringResource("previous match search again back"), symbol: "chevron.up",
        defaultShortcuts: [
            ShortcutDefault(
                platform: DevicePlatform.desktop,
                keys: KeyCombination(key: "g", isSpecialKey: false, modifiers: [.command, .shift])
            )
        ], availability: .webPage)

    static let all: [ShortcutCommand] = [
        newWindow,
        newBlankWindow,
        newTab,
        newPrivateWindow,
        closeTabOrWindow,
        closeWindow,
        openLocation,
        back,
        forward,
        reloadPage,
        stopLoading,
        reloadFromOrigin,
        toggleSelectedTabPinned,
        duplicateTab,
        reopenClosedTab,
        clearUnpinnedTabs,
        archiveTab,
        previousTab,
        nextTab,
        mostRecentTab,
        mostRecentTabBackward,
        selectTab1,
        selectTab2,
        selectTab3,
        selectTab4,
        selectTab5,
        selectTab6,
        selectTab7,
        selectTab8,
        selectTab9,
        previousSpace,
        nextSpace,
        selectSpace1,
        selectSpace2,
        selectSpace3,
        selectSpace4,
        selectSpace5,
        selectSpace6,
        selectSpace7,
        selectSpace8,
        selectSpace9,
        toggleReaderMode,
        toggleContentBlocking,
        findInPage,
        zoomIn,
        zoomOut,
        actualSize,
        copyPageLink,
        copyPageLinkAsMarkdown,
        sharePage,
        exportPDF,
        saveWebArchive,
        printPage,
        toggleSidebar,
        showHistory,
        showArchive,
        showDownloads,
        showWebInspector,
        splitWithNextTab,
        focusNextSplitCard,
        focusPreviousSplitCard,
        removeTabFromSplit,
        separateSplitTabs,
        moveSplitCardLeft,
        moveSplitCardRight,
        toggleDeveloperToolbar,
        translatePage,
        openFile,
        findNext,
        findPrevious,
    ]

    static func named(_ name: String?) -> Self? { all.first { $0.name == name } }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    private static func everywhere(_ keys: KeyCombination) -> [ShortcutDefault] {
        DevicePlatform.all.map { ShortcutDefault(platform: $0, keys: keys) }
    }
}
