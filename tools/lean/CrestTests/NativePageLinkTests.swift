import Foundation
import XCTest

@testable import Crest

final class NativePageLinkTests: XCTestCase {
    private func decide(
        _ url: String? = "https://example.com/", user: Bool = true, top: Bool = true,
        modifiers: ShortcutModifiers = [], middle: Bool = false, owned: Bool = true,
        placement: TabPlacement? = .saved, saved: String? = "https://apple.com/"
    ) -> LinkNavigationDecision {
        PageLinkDecision.resolve(
            url, gesture: LinkGesture(userActivated: user, topLevel: top, modifiers: modifiers, middleClick: middle),
            hasContext: owned, placement: placement, saved: saved)
    }
    func testSavedSiteProtectionPreservesHostsPlacementAndInternationalSpellings() {
        for (url, placement, expected): (String, TabPlacement?, LinkNavigationDecision) in [
            ("https://www.apple.com/news/", .saved, .navigate), ("http://APPLE.com:8080/news/", .pinned, .navigate),
            ("https://developer.apple.com/", .saved, .foregroundTab), ("https://example.com/", .pinned, .foregroundTab),
            ("https://example.com/", nil, .navigate), ("mailto:test@example.com", .saved, .navigate),
            ("file:///tmp/example.html", .saved, .navigate), ("crest://extensions/", .saved, .navigate),
        ] { XCTAssertEqual(decide(url, placement: placement), expected, url) }
        XCTAssertEqual(decide("https://www.xn--bcher-kva.example/page", saved: "https://bücher.example/"), .navigate)
        XCTAssertEqual(decide(saved: nil), .navigate)
        XCTAssertEqual(decide(nil), .navigate)
        XCTAssertEqual(decide(user: false), .navigate)
        XCTAssertEqual(decide(top: false), .navigate)
        XCTAssertEqual(decide(owned: false), .navigate)
    }
    func testPreviewNewTabModifiersAndMiddleClickMatchCrest() {
        XCTAssertEqual(decide(modifiers: .option), .foregroundTab)
        XCTAssertEqual(decide(modifiers: [.option, .command]), .foregroundTab)
        XCTAssertEqual(decide(modifiers: .option, owned: false), .navigate)
        XCTAssertEqual(decide(top: false, modifiers: .option), .navigate)
        XCTAssertEqual(decide(user: false, modifiers: .option), .navigate)
        XCTAssertEqual(decide("javascript:alert(1)", modifiers: .option), .navigate)
        XCTAssertEqual(decide(modifiers: .command), .backgroundTab)
        XCTAssertEqual(decide(modifiers: [.command, .shift]), .foregroundTab)
        XCTAssertEqual(decide(middle: true), .backgroundTab)
        XCTAssertEqual(decide(modifiers: .shift, middle: true), .foregroundTab)
        for modifiers: ShortcutModifiers in [[], .command, .shift, [.command, .shift]] {
            for middle in [false, true] {
                let gesture = LinkGesture(
                    userActivated: false, topLevel: true, modifiers: modifiers, middleClick: middle)
                XCTAssertEqual(
                    PageLinkDecision.selectsWindow(gesture),
                    !(modifiers.contains(.command) || middle) || modifiers.contains(.shift))
            }
        }
    }
}
