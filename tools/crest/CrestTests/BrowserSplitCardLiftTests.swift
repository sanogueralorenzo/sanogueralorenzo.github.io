import CoreGraphics
import Foundation
import SwiftUI
import XCTest

@testable import Crest

/// "Fancy Move": when a ⇧⌘-held press picks a Split View card up, which slot
/// the gap it leaves is standing in, and how the row is drawn around it.
///
/// The gesture itself is a local `NSEvent` monitor no test can drive, which is
/// exactly why every decision it makes is a pure function. These are the
/// contract for those decisions.
final class BrowserSplitCardLiftTests: XCTestCase {

    // MARK: - Pickup

    /// Everything the ⇧⌘ pair is not. Plain ⌘-click still opens a link in a new
    /// tab, ⌥-click still downloads, ⌃-click is still a right-click, and adding
    /// a third modifier to ⇧⌘ hands the press back to the page rather than
    /// widening the carry's claim.
    func testEveryOtherModifierCombinationIsLeftToThePage() {
        XCTAssertFalse(Self.picksUp(modifiers: .command))
        XCTAssertFalse(Self.picksUp(modifiers: .shift))
        XCTAssertFalse(Self.picksUp(modifiers: .option))
        XCTAssertFalse(Self.picksUp(modifiers: .control))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .option]))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .shift, .option]))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .shift, .control]))
    }

    // MARK: - Divider proximity

    // MARK: - The gap the carried card leaves

    // MARK: - The row as it is drawn

    // MARK: - Which card the press landed in

    // MARK: - Fixtures

    private static func picksUp(
        modifiers: BrowserKeyboardModifierFlags = [.command, .shift],
        isInsideCard: Bool = true,
        isOverDivider: Bool = false,
        memberCount: Int = 2,
        isDraggingSidebarItem: Bool = false,
        isCommandPalettePresented: Bool = false
    ) -> Bool {
        BrowserSplitCardLift.picksUp(
            modifiers: modifiers,
            isInsideCard: isInsideCard,
            isOverDivider: isOverDivider,
            memberCount: memberCount,
            isDraggingSidebarItem: isDraggingSidebarItem,
            isCommandPalettePresented: isCommandPalettePresented
        )
    }

    private static func isOverDivider(atX x: CGFloat, in cards: [CGRect]) -> Bool {
        BrowserSplitCardLift.isOverDivider(
            CGPoint(x: x, y: 300),
            orderedCardFrames: cards
        )
    }

    private static func gapIndex(
        atX x: CGFloat,
        in frames: [UUID: CGRect],
        lifted: UUID,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> Int {
        BrowserSplitCardLift.gapIndex(
            at: CGPoint(x: x, y: 300),
            cardFrames: frames,
            lifted: lifted,
            layoutDirection: layoutDirection
        )
    }

    /// Three 300pt cards with an 8pt gap: midpoints at 150, 458, and 766.
    private static func cardFrames(count: Int) -> [CGRect] {
        frames(widths: Array(repeating: 300, count: count))
    }

    private static func registeredFrames(count: Int) -> [UUID: CGRect] {
        registeredFrames(
            members: Array(BrowserSplitCardTestFixture.members.prefix(count)),
            widths: Array(repeating: 300, count: count)
        )
    }

    /// Card frames as the row would register them for `members` in the order
    /// given: the first member in the leading column, and so on.
    private static func registeredFrames(
        members: [BrowserSplitCardTestFixture.Member],
        widths: [CGFloat]
    ) -> [UUID: CGRect] {
        Dictionary(
            uniqueKeysWithValues: zip(members.map(\.id), frames(widths: widths))
        )
    }

    private static func frames(widths: [CGFloat]) -> [CGRect] {
        let gap = BrowserSplitLayoutMetrics.interCardGap
        var origin: CGFloat = 0
        var frames: [CGRect] = []
        for width in widths {
            frames.append(CGRect(x: origin, y: 0, width: width, height: 600))
            origin += width + gap
        }
        return frames
    }
}

/// The carry itself: what a pickup stages, what promotes it into a carry, what a
/// pointer sample changes, when the snapshot is allowed to arrive, and what a
/// release, a cancel, and every interruption each leave behind.
@MainActor
final class BrowserSplitCardLiftStateTests: XCTestCase {

    // MARK: - Staging and promotion

    // MARK: - The carry

    // MARK: - The picture

    // MARK: - Release, cancel, abandon

    // MARK: - Totality

    // MARK: - Fixtures

    private static let tabID = BrowserSplitCardTestFixture.middleTabID
    private static func token(of state: BrowserSplitCardLiftState) -> BrowserSplitCardLiftToken {
        state.lift?.token ?? BrowserSplitCardLiftToken(sequence: 0)
    }

}

private enum BrowserSplitCardTestFixture {
    static let leadingTabID = tabID(0x11)
    static let middleTabID = tabID(0x12)
    static let trailingTabID = tabID(0x13)

    static let members = [
        member(id: leadingTabID, title: "Release Notes"),
        member(id: middleTabID, title: "Layout Research"),
        member(id: trailingTabID, title: "Split View Spec"),
    ]

    /// A card of the row: only its identity matters to the lift.
    struct Member: Identifiable, Equatable {
        let id: UUID
        let title: String
    }

    private static func member(id: UUID, title: String) -> Member {
        Member(id: id, title: title)
    }

    private static func tabID(_ finalByte: UInt8) -> UUID {
        uuid(finalByte)
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x54,
                0x45, 0x53,
                0x54, 0x53,
                0x50, 0x4C, 0x49, 0x54, 0x00, finalByte
            ))
    }
}
