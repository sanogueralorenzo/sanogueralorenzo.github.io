import Foundation
import Observation

@Observable @MainActor
final class BrowserGettingStartedState {
    let practice = BrowserGettingStartedPractice()
    let scroll = BrowserNativeScrollState()
    var chapter = BrowserGettingStartedChapter.tabs
    var lesson = BrowserGettingStartedLesson.pin
}

/// The chapters of the Mac guide, in the order its picker shows them.
struct BrowserGettingStartedChapter: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let tabs = BrowserGettingStartedChapter(
        number: 1, name: "tabs", pickerTitle: "Tabs & folders", title: "Tabs and folders",
        introduction: "Pinned apps stay at the top, saved tabs above the line, and open tabs below it.",
        showsLessons: true, showsSplit: false)
    static let splitView = BrowserGettingStartedChapter(
        number: 2, name: "splitView", pickerTitle: "Split View", title: "Split View",
        introduction: "View pages side by side, change focus, and rearrange cards.",
        showsLessons: false, showsSplit: true)

    /// Every chapter, in the order the guide teaches them.
    static let all: [BrowserGettingStartedChapter] = [tabs, splitView]

    // MARK: - Variables

    /// The chapter's place in the guide, counted from one.
    let number: Int
    let name: String

    /// The chapter's name in the picker, where it is short.
    let pickerTitle: LocalizedStringResource
    let title: LocalizedStringResource
    let introduction: LocalizedStringResource

    /// Whether the chapter teaches lessons in a column beside the practice
    /// window.
    let showsLessons: Bool

    /// Whether the practice window shows a Split View. Arriving at such a
    /// chapter starts the practice over, so its split begins from the example
    /// tabs.
    let showsSplit: Bool

    var id: String { name }

    /// The chapter after this one, if any.
    var next: BrowserGettingStartedChapter? {
        Self.all.first { $0.number == number + 1 }
    }

    // MARK: - Initializers

    private init(
        number: Int, name: String, pickerTitle: LocalizedStringResource, title: LocalizedStringResource,
        introduction: LocalizedStringResource, showsLessons: Bool, showsSplit: Bool
    ) {
        self.number = number
        self.name = name
        self.pickerTitle = pickerTitle
        self.title = title
        self.introduction = introduction
        self.showsLessons = showsLessons
        self.showsSplit = showsSplit
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserGettingStartedChapter, rhs: BrowserGettingStartedChapter) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// The lessons of the tabs chapter, as the Mac guide teaches them with a
/// pointer and the touch guide with a finger.
struct BrowserGettingStartedLesson: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each lesson offers its own practice actions. Each guide switches on the
    /// kind to choose that lesson's concrete actions view.
    enum Kinds: Sendable {
        case pin
        case save
        case folders
        case clear
    }

    // MARK: - Static Variables

    static let pin = BrowserGettingStartedLesson(
        kind: .pin, number: 1, name: "pin", title: "Pin everyday apps",
        detail:
            "Pinned tabs live at the top and are for your everyday apps. Right-click Gmail and choose Pin Tab, or use the button below.",
        touchDetail: "Touch and hold Gmail, then choose Pin Tab. Pinned tabs stay at the top for your everyday apps.")
    static let save = BrowserGettingStartedLesson(
        kind: .save, number: 2, name: "save", title: "Save a tab",
        detail:
            "Saved tabs stay below your pins until you delete them. Save A weekend away and watch it move above the line.",
        touchDetail:
            "Saved tabs stay above the line until you delete them. The minus button unloads a saved tab while keeping it in your sidebar."
    )
    static let folders = BrowserGettingStartedLesson(
        kind: .folders, number: 3, name: "folders", title: "Create folders and nested folders",
        touchTitle: "Organize with folders",
        detail:
            "Folders can hold tabs and other folders. Add Weekends, then put Ideas inside it. You can also use folders below the line for open tabs.",
        touchDetail:
            "Folders hold tabs and other folders. Add Weekends, then nest Ideas inside it. Folders also work below the line with open tabs."
    )
    static let clear = BrowserGettingStartedLesson(
        kind: .clear, number: 4, name: "clear", title: "Clear open tabs",
        detail:
            "Below the line are open tabs. They close automatically on your Space's cleanup schedule. Clear sends them to Archive in one click; your pinned and saved tabs stay put.",
        touchDetail:
            "Tabs below the line close automatically on your Space’s cleanup schedule. Open the Space’s ••• menu and choose Clean Up Current Tabs to archive them now. Pinned and saved tabs stay."
    )

    /// Every lesson, in the order the guide teaches them.
    static let all: [BrowserGettingStartedLesson] = [pin, save, folders, clear]

    // MARK: - Variables

    let kind: Kinds

    /// The lesson's place in the chapter, counted from one.
    let number: Int
    let name: String

    /// The lesson as the Mac guide teaches it.
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    /// The lesson as the touch guide teaches it.
    let touchTitle: LocalizedStringResource
    let touchDetail: LocalizedStringResource

    var id: String { name }

    /// The lesson after this one, if any.
    var next: BrowserGettingStartedLesson? {
        Self.all.first { $0.number == number + 1 }
    }

    /// The lesson before this one, if any.
    var previous: BrowserGettingStartedLesson? {
        Self.all.first { $0.number == number - 1 }
    }

    // MARK: - Initializers

    private init(
        kind: Kinds, number: Int, name: String, title: LocalizedStringResource,
        touchTitle: LocalizedStringResource? = nil, detail: LocalizedStringResource,
        touchDetail: LocalizedStringResource
    ) {
        self.kind = kind
        self.number = number
        self.name = name
        self.title = title
        self.detail = detail
        self.touchTitle = touchTitle ?? title
        self.touchDetail = touchDetail
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserGettingStartedLesson, rhs: BrowserGettingStartedLesson) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
