import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserMacMouseButtonsTests: XCTestCase {
    // MARK: - Types

    /// A window's content that takes the presses it is offered while
    /// `takesPresses` says so.
    private final class Content: BrowserMacWindowPointerNavigation {
        var takesPresses: Bool
        private(set) var presses: [BrowserSidebarMouseButtonAction] = []

        init(takesPresses: Bool) {
            self.takesPresses = takesPresses
        }

        func takePress(_ action: BrowserSidebarMouseButtonAction, at event: NSEvent) -> Bool {
            presses.append(action)
            return takesPresses
        }

        func navigate(_ action: BrowserSidebarMouseButtonAction, swipedAt event: NSEvent) -> Bool {
            false
        }
    }

    // MARK: - Actions - Tests

    /// Chromium goes back or forward again on a Back or Forward release it
    /// sees, so the release of a press Crest acted on must never reach the
    /// page, even when SwiftUI rebuilt the window's content in between.
    func testTakenClickIsTakenWholeAfterTheWindowContentIsRebuilt() throws {
        var content: Content? = Content(takesPresses: true)
        let buttons = BrowserMacMouseButtons(navigation: { _ in content })

        XCTAssertTrue(buttons.take(try event(.otherMouseDown, button: 3)))
        XCTAssertEqual(content?.presses, [.previousSpace])
        content = nil

        XCTAssertTrue(buttons.take(try event(.otherMouseDragged, button: 3)))
        XCTAssertTrue(buttons.take(try event(.otherMouseUp, button: 3)))
        XCTAssertFalse(buttons.take(try event(.otherMouseUp, button: 3)))
    }

    // MARK: - Actions - Events

    private func event(_ type: CGEventType, button: Int64) throws -> NSEvent {
        let event = try XCTUnwrap(
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: .center))
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }
}
