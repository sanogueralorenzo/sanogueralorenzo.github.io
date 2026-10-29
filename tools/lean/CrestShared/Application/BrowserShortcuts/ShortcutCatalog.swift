import Foundation

enum ShortcutMenu: String, CaseIterable, Sendable {
    case file, view, navigate, tabs, spaces, page, develop

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var title: LocalizedStringResource {
        switch self {
        case .file: LocalizedStringResource("File")
        case .view: LocalizedStringResource("View")
        case .navigate: LocalizedStringResource("Navigate")
        case .tabs: LocalizedStringResource("Tabs")
        case .spaces: LocalizedStringResource("Spaces")
        case .page: LocalizedStringResource("Page")
        case .develop: LocalizedStringResource("Develop")
        }
    }

    var groups: [[ShortcutCommand]] {
        switch self {
        case .file:
            [
                [
                    ShortcutCommand.newWindow,
                    ShortcutCommand.newBlankWindow,
                    ShortcutCommand.newTab,
                    ShortcutCommand.newPrivateWindow,
                ],
                [ShortcutCommand.openFile],
                [ShortcutCommand.closeTabOrWindow, ShortcutCommand.closeWindow],
                [ShortcutCommand.printPage],
            ]
        case .view:
            [
                [ShortcutCommand.toggleSidebar, ShortcutCommand.translatePage],
                [ShortcutCommand.showHistory, ShortcutCommand.showArchive, ShortcutCommand.showDownloads],
            ]
        case .navigate:
            [
                [ShortcutCommand.openLocation],
                [
                    ShortcutCommand.back,
                    ShortcutCommand.forward,
                    ShortcutCommand.reloadPage,
                    ShortcutCommand.stopLoading,
                    ShortcutCommand.reloadFromOrigin,
                ],
            ]
        case .tabs:
            [
                [
                    ShortcutCommand.toggleSelectedTabPinned,
                    ShortcutCommand.duplicateTab,
                    ShortcutCommand.reopenClosedTab,
                    ShortcutCommand.clearUnpinnedTabs,
                    ShortcutCommand.archiveTab,
                ],
                [
                    ShortcutCommand.previousTab,
                    ShortcutCommand.nextTab,
                    ShortcutCommand.mostRecentTab,
                    ShortcutCommand.mostRecentTabBackward,
                ],
                [
                    ShortcutCommand.splitWithNextTab,
                    ShortcutCommand.focusNextSplitCard,
                    ShortcutCommand.focusPreviousSplitCard,
                    ShortcutCommand.moveSplitCardLeft,
                    ShortcutCommand.moveSplitCardRight,
                    ShortcutCommand.removeTabFromSplit,
                    ShortcutCommand.separateSplitTabs,
                ],
                [
                    ShortcutCommand.selectTab1,
                    ShortcutCommand.selectTab2,
                    ShortcutCommand.selectTab3,
                    ShortcutCommand.selectTab4,
                    ShortcutCommand.selectTab5,
                    ShortcutCommand.selectTab6,
                    ShortcutCommand.selectTab7,
                    ShortcutCommand.selectTab8,
                    ShortcutCommand.selectTab9,
                ],
            ]
        case .spaces:
            [
                [ShortcutCommand.previousSpace, ShortcutCommand.nextSpace],
                [
                    ShortcutCommand.selectSpace1,
                    ShortcutCommand.selectSpace2,
                    ShortcutCommand.selectSpace3,
                    ShortcutCommand.selectSpace4,
                    ShortcutCommand.selectSpace5,
                    ShortcutCommand.selectSpace6,
                    ShortcutCommand.selectSpace7,
                    ShortcutCommand.selectSpace8,
                    ShortcutCommand.selectSpace9,
                ],
            ]
        case .page:
            [
                [ShortcutCommand.toggleReaderMode, ShortcutCommand.toggleContentBlocking],
                [ShortcutCommand.findInPage, ShortcutCommand.findNext, ShortcutCommand.findPrevious],
                [ShortcutCommand.zoomIn, ShortcutCommand.zoomOut, ShortcutCommand.actualSize],
                [
                    ShortcutCommand.copyPageLink,
                    ShortcutCommand.copyPageLinkAsMarkdown,
                    ShortcutCommand.sharePage,
                    ShortcutCommand.exportPDF,
                    ShortcutCommand.saveWebArchive,
                ],
            ]
        case .develop: [[ShortcutCommand.toggleDeveloperToolbar], [ShortcutCommand.showWebInspector]]
        }
    }
}

enum ShortcutSection: String, CaseIterable, Sendable {
    case everyday, tabs, spaces, page, view

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var title: LocalizedStringResource {
        switch self {
        case .everyday: LocalizedStringResource("Everyday Use")
        case .tabs: LocalizedStringResource("Tabs")
        case .spaces: LocalizedStringResource("Spaces")
        case .page: LocalizedStringResource("Page")
        case .view: LocalizedStringResource("View & Tools")
        }
    }
}

enum ShortcutSpecialKey: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case tab, leftArrow, rightArrow, upArrow, downArrow, escape, returnKey, delete, forwardDelete, home, end, pageUp,
        pageDown, space, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var glyph: String? {
        switch self {
        case .tab: "⇥"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .escape: "⎋"
        case .returnKey: "↩"
        case .delete: "⌫"
        case .forwardDelete: "⌦"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        case .space: nil
        case .f1: "F1"
        case .f2: "F2"
        case .f3: "F3"
        case .f4: "F4"
        case .f5: "F5"
        case .f6: "F6"
        case .f7: "F7"
        case .f8: "F8"
        case .f9: "F9"
        case .f10: "F10"
        case .f11: "F11"
        case .f12: "F12"
        case .f13: "F13"
        case .f14: "F14"
        case .f15: "F15"
        case .f16: "F16"
        case .f17: "F17"
        case .f18: "F18"
        case .f19: "F19"
        case .f20: "F20"
        }
    }

    var title: LocalizedStringResource? {
        switch self {
        case .tab: nil
        case .leftArrow: nil
        case .rightArrow: nil
        case .upArrow: nil
        case .downArrow: nil
        case .escape: nil
        case .returnKey: nil
        case .delete: nil
        case .forwardDelete: nil
        case .home: nil
        case .end: nil
        case .pageUp: nil
        case .pageDown: nil
        case .space: LocalizedStringResource("Space")
        case .f1: nil
        case .f2: nil
        case .f3: nil
        case .f4: nil
        case .f5: nil
        case .f6: nil
        case .f7: nil
        case .f8: nil
        case .f9: nil
        case .f10: nil
        case .f11: nil
        case .f12: nil
        case .f13: nil
        case .f14: nil
        case .f15: nil
        case .f16: nil
        case .f17: nil
        case .f18: nil
        case .f19: nil
        case .f20: nil
        }
    }

    var spokenName: LocalizedStringResource? {
        switch self {
        case .tab: LocalizedStringResource("tab")
        case .leftArrow: LocalizedStringResource("left arrow")
        case .rightArrow: LocalizedStringResource("right arrow")
        case .upArrow: LocalizedStringResource("up arrow")
        case .downArrow: LocalizedStringResource("down arrow")
        case .escape: LocalizedStringResource("escape")
        case .returnKey: LocalizedStringResource("return")
        case .delete: LocalizedStringResource("delete")
        case .forwardDelete: LocalizedStringResource("forward delete")
        case .home: LocalizedStringResource("home")
        case .end: LocalizedStringResource("end")
        case .pageUp: LocalizedStringResource("page up")
        case .pageDown: LocalizedStringResource("page down")
        case .space: LocalizedStringResource("space")
        case .f1: nil
        case .f2: nil
        case .f3: nil
        case .f4: nil
        case .f5: nil
        case .f6: nil
        case .f7: nil
        case .f8: nil
        case .f9: nil
        case .f10: nil
        case .f11: nil
        case .f12: nil
        case .f13: nil
        case .f14: nil
        case .f15: nil
        case .f16: nil
        case .f17: nil
        case .f18: nil
        case .f19: nil
        case .f20: nil
        }
    }

    var functionKeyNumber: Int? {
        switch self {
        case .tab: nil
        case .leftArrow: nil
        case .rightArrow: nil
        case .upArrow: nil
        case .downArrow: nil
        case .escape: nil
        case .returnKey: nil
        case .delete: nil
        case .forwardDelete: nil
        case .home: nil
        case .end: nil
        case .pageUp: nil
        case .pageDown: nil
        case .space: nil
        case .f1: 1
        case .f2: 2
        case .f3: 3
        case .f4: 4
        case .f5: 5
        case .f6: 6
        case .f7: 7
        case .f8: 8
        case .f9: 9
        case .f10: 10
        case .f11: 11
        case .f12: 12
        case .f13: 13
        case .f14: 14
        case .f15: 15
        case .f16: 16
        case .f17: 17
        case .f18: 18
        case .f19: 19
        case .f20: 20
        }
    }
}

enum NumberedSelectionTarget: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case tab, space

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }
    typealias Kinds = NumberedSelectionTarget
    var kind: Kinds { self }
}
