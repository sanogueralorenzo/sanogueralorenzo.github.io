import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteModelActivationTests: XCTestCase {
    func testSuggestionNetworkConfigurationCarriesNoCookiesOrSharedCache() {
        let configuration = BrowserSearchSuggestionClient.sessionConfiguration

        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertLessThanOrEqual(configuration.timeoutIntervalForRequest, 5)
    }

    private func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x50,
                0x41, 0x4C,
                0x45, 0x54,
                0x54, 0x45, 0x4D, 0x4F, 0x44, finalByte
            ))
    }
}
