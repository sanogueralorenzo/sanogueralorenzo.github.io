import Foundation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserFaviconRenderSafetyTests: XCTestCase {
    func testStartPageAndEmojiRequestsNeverInvokeNetworkFallback() async {
        let fallback = RecordingFallback()
        let profileID = fixedUUID(tail: 0x90)
        let subjects = [
            subject(TabState.Seed.startPage(id: tabID(tail: 0x10), lastActivatedAt: epoch)),
            subject(
                TabState.Seed(
                    id: tabID(tail: 0x20),
                    title: "Emoji",
                    url: URL(string: "https://emoji.invalid/page"),
                    symbol: BrowserIconSymbol.symbol(forEmoji: "🧭"),
                    iconMode: .emoji,
                    placement: .current,
                    lastActivatedAt: epoch
                )),
        ]

        for subject in subjects {
            let request = subject.renderRequest(profileID: profileID, maximumPixelSize: 64)
            let result = await BrowserFaviconRenderLoader.decode(
                request,
                fallbackData: fallback.data
            )
            XCTAssertNil(result)
        }

        let requestCount = await fallback.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testLockedSpaceRequestCarriesNoNetworkFallback() async {
        let fallback = RecordingFallback()
        let tab = makeSubject(
            id: tabID(tail: 0x41),
            url: URL(string: "https://private.invalid/page"),
            data: nil,
            iconMode: .automatic
        )
        let request = tab.renderRequest(profileID: fixedUUID(tail: 0x91), maximumPixelSize: 64, isUnlocked: false)
        XCTAssertNil(request.fallbackPageURL)
        XCTAssertNil(request.fallbackProfileID)

        let result = await BrowserFaviconRenderLoader.decode(
            request,
            fallbackData: fallback.data
        )
        XCTAssertNil(result)
        let requestCount = await fallback.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testCancelledOlderRequestStartingLateCannotClearOrReplaceNewerImage() {
        let tab = makeSubject(
            id: tabID(tail: 0x31),
            url: URL(string: "https://identity.invalid/race"),
            data: Data([0x01, 0x02, 0x03]),
            iconMode: .automatic
        )
        let older = tab.taskIdentity(profileID: fixedUUID(tail: 0xA2), maximumPixelSize: 64)
        let newer = tab.taskIdentity(profileID: fixedUUID(tail: 0xA3), maximumPixelSize: 64)
        var state = BrowserFaviconRenderState()

        state.begin(older, isCancelled: false)
        state.begin(newer, isCancelled: false)
        state.publish(
            Image(systemName: "checkmark.seal.fill"),
            for: newer,
            isCancelled: false
        )
        state.begin(older, isCancelled: true)
        state.publish(
            Image(systemName: "xmark.seal.fill"),
            for: older,
            isCancelled: true
        )

        XCTAssertNotNil(state.renderedImage?.image(matching: newer))
        XCTAssertNil(state.renderedImage?.image(matching: older))
    }

    private let epoch = Date(timeIntervalSince1970: 0)

    private func makeSubject(
        id: UUID,
        url: URL?,
        data: Data?,
        iconMode: TabIconMode
    ) -> BrowserTabFaviconSubject {
        subject(
            TabState.Seed(
                id: id, title: "Identity", url: url, iconMode: iconMode, placement: .current, lastActivatedAt: epoch),
            image: data)
    }

    /// `tab` as the core resolves it, wearing `image`.
    private func subject(_ tab: TabState.Seed, image: Data? = nil) -> BrowserTabFaviconSubject {
        let model = SpaceModel.detached(SpaceState.Seed(name: "Icons", tabs: [tab])).tabs.models[0]
        return BrowserTabFaviconSubject(tab: model, image: image.map(FaviconAssets.Image.init))
    }

    private func tabID(tail: UInt8) -> UUID {
        fixedUUID(tail: tail)
    }

    private func fixedUUID(tail: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, tail))
    }

    private actor RecordingFallback {
        private(set) var requestCount = 0

        func data(pageURL _: URL, profileID _: UUID) async -> Data? {
            requestCount += 1
            return nil
        }
    }
}
