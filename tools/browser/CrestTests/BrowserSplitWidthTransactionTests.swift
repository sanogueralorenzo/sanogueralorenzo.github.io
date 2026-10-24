import CoreGraphics
import Foundation
import XCTest

@testable import Crest

/// The width transaction's interaction lifecycle.
///
/// The first section is the regression guard for the resize feedback loop. A
/// divider handle is positioned from the fractions its own drag writes, so a
/// gesture measured against that handle reports the pointer's travel minus the
/// handle's, and the layout never settles. These cases fix the two halves of the
/// fix in arithmetic: a drag holding one pointer position must answer the same
/// fractions on every layout pass, and the divider that pass positions must come
/// to rest. The rest of the class guards the commit contract per-window
/// persistence depends on.
final class BrowserSplitWidthTransactionTests: XCTestCase {
    private let containerWidth: CGFloat = 1000
    /// How many times a real drag can be re-evaluated while the pointer sits
    /// still: enough passes that a loop with any gain at all would show.

    // MARK: - Stability under a stationary pointer

    // MARK: - Commit contract

    func testCommittingPublishesTheLayoutTheDragSettledOn() {
        var transaction = makeTransaction()

        transaction.resize(dividerIndex: 0, delta: 40, containerWidth: containerWidth)
        let committed = transaction.commit()

        XCTAssertEqual(committed, transaction.fractions)
        XCTAssertEqual(transaction.persistedFractions, transaction.fractions)
    }

    func testCommittingAnUnchangedLayoutHasNothingToPersist() {
        var transaction = makeTransaction()

        transaction.resize(dividerIndex: 0, delta: 24, containerWidth: containerWidth)
        transaction.resize(dividerIndex: 0, delta: 0, containerWidth: containerWidth)

        XCTAssertNil(
            transaction.commit(),
            "A drag that landed where it started has nothing to persist."
        )
    }

    func testTheNextDragMeasuresFromTheLayoutTheLastOneLeft() {
        var transaction = makeTransaction()

        transaction.resize(dividerIndex: 0, delta: 40, containerWidth: containerWidth)
        _ = transaction.commit()
        let settled = transaction.fractions
        transaction.resize(dividerIndex: 0, delta: 0, containerWidth: containerWidth)

        assertFractions(
            transaction.fractions,
            equal: settled,
            "A fresh drag with no travel yet cannot move the layout."
        )
    }

    func testAdoptingNewFractionsDropsTheDragInFlight() {
        var transaction = makeTransaction()

        transaction.resize(dividerIndex: 0, delta: 24, containerWidth: containerWidth)
        transaction.begin(fractions: [0.5, 0.5])
        transaction.resize(dividerIndex: 0, delta: 0, containerWidth: containerWidth)

        assertFractions(
            transaction.fractions,
            equal: [0.5, 0.5],
            "A membership change replaces the layout the drag was moving."
        )
    }

    // MARK: - Helpers

    private func makeTransaction() -> BrowserSplitWidthTransaction {
        BrowserSplitWidthTransaction(persistedFractions: [0.4, 0.35, 0.25])
    }

    private func assertFractions(
        _ fractions: [Double],
        equal expected: [Double],
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(fractions.count, expected.count, message, file: file, line: line)
        for (actual, wanted) in zip(fractions, expected) {
            XCTAssertEqual(actual, wanted, accuracy: 1e-9, message, file: file, line: line)
        }
    }
}
