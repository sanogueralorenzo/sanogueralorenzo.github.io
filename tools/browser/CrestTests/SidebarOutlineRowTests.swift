import Foundation
import XCTest

@testable import Crest

/// The rows the sidebar draws, as the core's outline lists them and the
/// sidebar's list items read them: a split's run is one row, a lone member is
/// a tab, and a row's following tab is what a drop below it lands before.
@MainActor
final class SidebarOutlineRowTests: XCTestCase {
    func testAContiguousRunFoldsIntoOneGroupRow() throws {
        let group = Self.uuid(0x01)
        let first = makeTab(0x11, "First", group: group)
        let second = makeTab(0x12, "Second", group: group)
        let third = makeTab(0x13, "Third", group: group)

        let rows = try rows(of: [first, second, third])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.map(\.members), [[first.id, second.id, third.id]])
        XCTAssertEqual(rows.map(BrowserSidebarReorderItemID.init), [.splitGroup(group)])
    }

    /// Storage keeps a lone member's ID so a staggered sync can reconstitute the
    /// group; the sidebar must still draw it as an ordinary tab.
    func testASingletonMemberStaysAPlainTab() throws {
        let group = Self.uuid(0x02)
        let lone = makeTab(0x21, "Lone", group: group)
        let plain = makeTab(0x22, "Plain")

        let rows = try rows(of: [lone, plain])

        XCTAssertEqual(rows.map(\.kind), [.tab, .tab])
        XCTAssertEqual(rows.map(BrowserSidebarReorderItemID.init), [.tab(lone.id), .tab(plain.id)])
    }

    func testRowOrderAndMembershipFollowTheSessionArray() throws {
        let group = Self.uuid(0x03)
        let leading = makeTab(0x31, "Leading")
        let head = makeTab(0x32, "Head", group: group)
        let tail = makeTab(0x33, "Tail", group: group)
        let trailing = makeTab(0x34, "Trailing")

        let rows = try rows(of: [leading, head, tail, trailing])

        XCTAssertEqual(
            rows.map(BrowserSidebarReorderItemID.init), [.tab(leading.id), .splitGroup(group), .tab(trailing.id)])
        XCTAssertEqual(
            rows.flatMap(\.members),
            [leading.id, head.id, tail.id, trailing.id],
            "Folding must preserve every tab and its order."
        )
    }

    /// Defensive: a list carrying a group ID twice is malformed. It must never
    /// produce two rows claiming the same identity — `ForEach` would then have
    /// duplicate IDs.
    func testARepeatedGroupIDNeverProducesASecondGroupRow() throws {
        let group = Self.uuid(0x06)
        let head = makeTab(0x51, "Head", group: group)
        let tail = makeTab(0x52, "Tail", group: group)
        let interloper = makeTab(0x53, "Interloper")
        let strayHead = makeTab(0x54, "Stray Head", group: group)
        let strayTail = makeTab(0x55, "Stray Tail", group: group)

        let rows = try rows(of: [head, tail, interloper, strayHead, strayTail])

        XCTAssertEqual(rows.filter { $0.kind.groupsTabs }.map(\.members), [[head.id, tail.id]])
        XCTAssertEqual(
            Set(rows.map(BrowserSidebarReorderItemID.init)).count,
            rows.count,
            "Row identities must be unique."
        )
    }

    /// A group is one row, so the anchor a drop below it resolves to is the tab
    /// following its *last* member. An anchor landing inside the run is what
    /// would drop a foreign tab between two members and split the group.
    func testAGroupRowsTrailingDropAnchorSkipsPastEveryMember() throws {
        let group = Self.uuid(0x0C)
        let leading = makeTab(0xB1, "Leading")
        let head = makeTab(0xB2, "Head", group: group)
        let middle = makeTab(0xB3, "Middle", group: group)
        let tail = makeTab(0xB4, "Tail", group: group)
        let trailing = makeTab(0xB5, "Trailing")

        let items = try items(of: [leading, head, middle, tail, trailing])

        XCTAssertEqual(items.map(\.id), [.tab(leading.id), .splitGroup(group), .tab(trailing.id)])
        XCTAssertEqual(
            items[0].followingTabID,
            head.id,
            "The row above a group anchors on the group's first member."
        )
        XCTAssertEqual(
            items[1].followingTabID,
            trailing.id,
            "The row below a group anchors past its last member."
        )
    }

    /// A group closing a section has no following row, so its own trailing
    /// indicator is the only one drawn there — the same ownership rule an
    /// ordinary last row follows.
    func testAGroupClosingASectionHasNoFollowingRow() throws {
        let group = Self.uuid(0x0D)
        let head = makeTab(0xC1, "Head", group: group)
        let tail = makeTab(0xC2, "Tail", group: group)

        let followingTabID = try items(of: [head, tail])[0].followingTabID

        XCTAssertNil(followingTabID)
    }

    /// A collapsed folder's list still holds its rows, so the row it keeps on
    /// screen for the shown tab is the whole split the content presents.
    func testCollapsedFolderKeepsTheWholeSelectedSplitGroupVisible() throws {
        let group = Self.uuid(0x0E)
        let folder = FolderState.Seed(title: "Collapsed", isCollapsed: true)
        let head = makeTab(0xD1, "Head", group: group, placement: .saved, folderID: folder.id)
        let selected = makeTab(0xD2, "Selected", group: group, placement: .saved, folderID: folder.id)
        let neighbor = makeTab(0xD3, "Neighbor", placement: .saved, folderID: folder.id)
        var space = SpaceState.Seed.blank(number: 1)
        space.folders = [folder]
        space.tabs += [head, selected, neighbor]
        let session = SessionState.Seed(spaces: [space], defaultSpaceID: space.id)

        let store = BrowserStore(seed: session)
        let kept = try XCTUnwrap(
            store.spaceModel(space.id)?.sidebar.inside(folder.id).rows.first { $0.members.contains(selected.id) })

        XCTAssertEqual(
            kept.members,
            [head.id, selected.id],
            "The collapsed representation must match the split still presented in content."
        )
    }

    // MARK: - Fixtures

    /// The open tabs' top level for `tabs` opened in a Space of their own.
    private func rows(of tabs: [TabState.Seed]) throws -> [SidebarRow] {
        let (store, space) = try open(tabs)
        return try XCTUnwrap(store.spaceModel(space.id)).sidebar.section(.current).rows
    }

    /// The sidebar's list items for that top level, naming each row's
    /// following tab as a sidebar drawing drop seams names it.
    private func items(of tabs: [TabState.Seed]) throws -> [BrowserSidebarListItem] {
        let (store, space) = try open(tabs)
        let model = try XCTUnwrap(store.spaceModel(space.id))
        return BrowserSidebarListItem.items(of: model.sidebar.section(.current), in: model, namesFollowingTabs: true)
    }

    private func open(_ tabs: [TabState.Seed]) throws -> (BrowserStore, SpaceState.Seed) {
        var space = SpaceState.Seed.blank(number: 1)
        space.tabs = tabs
        let store = BrowserStore(seed: SessionState.Seed(spaces: [space], defaultSpaceID: space.id))
        return (store, space)
    }

    private func makeTab(
        _ finalByte: UInt8,
        _ title: String,
        group: UUID? = nil,
        placement: TabPlacement = .current,
        folderID: UUID? = nil
    ) -> TabState.Seed {
        TabState.Seed(
            id: Self.uuid(finalByte),
            title: title,
            url: URL(fileURLWithPath: "/crest-sidebar-item-policy/\(title)"),
            placement: placement,
            folderID: folderID,
            splitGroupID: group,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x49,
                0x54, 0x45, 0x4D, 0x53, 0x00, 0x00, 0x00, finalByte
            )
        )
    }
}
