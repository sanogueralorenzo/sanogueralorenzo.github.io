import Foundation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserFaviconRenderSafetyTests: XCTestCase {
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
