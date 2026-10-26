import Foundation
import XCTest

@testable import Crest

final class BrowserTabStateArchiveTests: XCTestCase {

    func testEngineStateKeepsChromiumAcrossVersionsButRejectsOtherEnginesAndWebKitBuilds() throws {
        let payload = Data("opaque engine history".utf8)
        let chromium = try XCTUnwrap(
            BrowserEngineInteractionState(
                engine: .chromium, version: "1", payload: payload
            ).encoded())
        let webkit = try XCTUnwrap(
            BrowserEngineInteractionState(
                engine: .webKit, version: "os-1", payload: payload
            ).encoded())

        XCTAssertEqual(BrowserEngineInteractionState.payload(chromium, engine: .chromium, version: "1"), payload)
        XCTAssertEqual(
            BrowserEngineInteractionState.payload(chromium, engine: .chromium, version: "2"), payload,
            "Chromium reads back history another version of it saved, so an engine update keeps it.")
        XCTAssertEqual(BrowserEngineInteractionState.payload(webkit, engine: .webKit, version: "os-1"), payload)
        XCTAssertNil(BrowserEngineInteractionState.payload(webkit, engine: .webKit, version: "os-2"))
        XCTAssertNil(BrowserEngineInteractionState.payload(chromium, engine: .webKit, version: "1"))
        XCTAssertNil(BrowserEngineInteractionState.payload(webkit, engine: .chromium, version: "os-1"))
        XCTAssertNil(BrowserEngineInteractionState.payload(chromium.dropLast(), engine: .chromium, version: "1"))
        XCTAssertNil(BrowserEngineInteractionState.payload(chromium.dropLast(), engine: .webKit, version: "1"))
        XCTAssertEqual(BrowserEngineInteractionState.payload(payload, engine: .webKit, version: "os-1"), payload)
        XCTAssertNil(BrowserEngineInteractionState.payload(payload, engine: .chromium, version: "1"))
        XCTAssertNil(BrowserEngineInteractionState(engine: .chromium, version: "1", payload: Data()).encoded())
    }

    func testTheCoresHistoryTravelsWithTheEngineStateAndEarlierFramesStillRestore() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        let state = Data("session".utf8)
        let history = Data("history".utf8)
        let current = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(interactionState: state, url: url, history: history).encoded()))
        let earlier = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(interactionState: state, url: url, history: history, formatVersion: 1)
                    .encoded()))

        XCTAssertEqual(current.history, history)
        XCTAssertEqual(current.interactionState, state)
        XCTAssertEqual(current.url, url)
        XCTAssertTrue(current.isRestorable)
        XCTAssertNil(earlier.history, "A version 1 frame, as earlier builds wrote it, carries no history.")
        XCTAssertEqual(earlier.interactionState, state)
        XCTAssertTrue(earlier.isRestorable)

        // A page with no engine state yet still keeps the core's history.
        let historyOnly = try XCTUnwrap(
            BrowserTabStateEnvelope.decode(
                BrowserTabStateEnvelope(interactionState: Data(), url: url, history: history).encoded()))
        XCTAssertEqual(historyOnly.history, history)
        XCTAssertTrue(historyOnly.isReadable)
        XCTAssertFalse(historyOnly.isRestorable, "An empty engine state is never handed to the engine.")
    }

    func testUnframedOrTruncatedDataDecodesToNothing() throws {
        let encoded = BrowserTabStateEnvelope(
            interactionState: Data("session".utf8),
            url: try XCTUnwrap(URL(string: "https://example.com/"))
        ).encoded()

        XCTAssertNil(BrowserTabStateEnvelope.decode(Data()))
        XCTAssertNil(BrowserTabStateEnvelope.decode(Data("not an envelope at all".utf8)))
        XCTAssertNil(
            BrowserTabStateEnvelope.decode(encoded.prefix(8)),
            "A file cut short must not decode into a partial session."
        )
        XCTAssertNil(
            BrowserTabStateEnvelope.decode(encoded.dropLast(encoded.count - 14)),
            "A header promising more bytes than the file holds must be refused."
        )
    }
}

/// The favicon side store the session core no longer carries bytes for.
final class BrowserFaviconFileStoreTests: XCTestCase {
}
