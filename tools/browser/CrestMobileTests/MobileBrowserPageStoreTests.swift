import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPageStoreTests: XCTestCase {

    // MARK: - Per-Space credential access

    func testDisablingCredentialAccessResetsAPendingFillRequest() throws {
        let session = makeSession(index: 3)
        let space = try XCTUnwrap(session.spaces.first)
        let browser = BrowserStore.hostingPages(session)
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        pages.select()
        let page = try XCTUnwrap(pages.activePage)
        let loginOrigin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        page.credentialState.receive(
            try submitMessage(),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: nil
        )
        page.credentialState.receive(
            try documentStateMessage(),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: nil
        )
        XCTAssertNotNil(page.credentialSaveCandidate)

        browser.updateCredentialPreferences(Self.savingOff, in: space.id)
        pages.reconcileCredentialAccess()

        XCTAssertFalse(page.isCredentialAccessEnabled)
        XCTAssertNil(
            page.credentialSaveCandidate,
            "Turning saving off mid-session must take the pending save offer away with it."
        )
    }

    func testDisabledCredentialAccessRejectsAFillAndStopsFormCapture() async throws {
        let session = makeSession(index: 4, savesCredentials: false)
        let browser = BrowserStore.hostingPages(session)
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        pages.select()
        let page = try XCTUnwrap(pages.activePage)
        let request = URLRequest(
            url: try XCTUnwrap(URL(string: "https://forms.crest.test/login"))
        )
        page.webView.loadSimulatedRequest(
            request,
            responseHTML: """
                <!doctype html>
                <style>input { display: block; width: 220px; height: 32px; }</style>
                <form id="mobile-login">
                  <input autocomplete="username" value="mobile@example.com">
                  <input type="password" autocomplete="current-password" value="mobile-secret">
                  <button type="button">Sign In</button>
                </form>
                """
        )
        try await waitUntil { page.completedNavigationCount == 1 }

        let didCapture = try await page.webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.captureForTesting(selector) === true;",
            arguments: ["selector": "#mobile-login"],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        XCTAssertEqual(didCapture as? Bool, true)
        _ = try await page.webView.callAsyncJavaScript(
            "document.querySelector('#mobile-login').remove(); return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertNil(
            page.credentialSaveCandidate,
            "A Space with saving off must never offer to save what a form submitted."
        )
        XCTAssertNil(page.credentialFillRequest)
        await assertThrowsErrorAsync(
            try await page.fillGeneratedPassword("generated", for: UUID())
        )
    }

    func testTransientPeekPagesFollowTheirSpacesCredentialPreference() throws {
        let session = makeSession(index: 5)
        let space = try XCTUnwrap(session.spaces.first)
        let browser = BrowserStore.hostingPages(session)
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        let lease = try XCTUnwrap(
            pages.makeTransientPageLease(
                url: try XCTUnwrap(URL(string: "about:blank")),
                in: try XCTUnwrap(browser.spaceModel(space.id))
            )
        )
        XCTAssertTrue(try XCTUnwrap(lease.page).isCredentialAccessEnabled)

        browser.updateCredentialPreferences(Self.savingOff, in: space.id)
        pages.reconcileCredentialAccess()

        XCTAssertFalse(try XCTUnwrap(lease.page).isCredentialAccessEnabled)
    }

    func testPrivateBrowsingKeepsCredentialAccessOffEvenWhenTheSpaceAllowsSaving() throws {
        let session = makeSession(index: 6)
        let pages = MobileBrowserPageStore(
            browser: .hostingPages(session, browsingMode: .privateBrowsing),
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )

        pages.select()

        XCTAssertFalse(try XCTUnwrap(pages.activePage).isCredentialAccessEnabled)
    }

    // MARK: - Memory pressure

    func testCriticalPressureEventReleasesTheActiveTransientLeaseAWarningKeeps() throws {
        let session = makeSession(index: 7)
        let space = try XCTUnwrap(session.spaces.first)
        let browser = BrowserStore.hostingPages(session)
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        let url = try XCTUnwrap(URL(string: "about:blank"))
        pages.select()
        let activeLease = try XCTUnwrap(
            pages.makeTransientPageLease(url: url, in: try XCTUnwrap(browser.spaceModel(space.id)))
        )
        // `dispatch_source_get_data` is only defined for the duration of the
        // event handler, so the level has to be captured there and passed in as a
        // value. Reading it back off the source after a hop is what made every
        // squeeze — critical included — arrive here as a warning.

        pages.handleMemoryPressureEvent([.warning])

        XCTAssertNotNil(
            activeLease.page,
            "A warning deliberately preserves the transient surface in use."
        )

        pages.handleMemoryPressureEvent([.critical])

        XCTAssertNil(
            activeLease.page,
            "Critical pressure must reach critical handling instead of collapsing to a warning."
        )
        XCTAssertTrue(activeLease.wasReleasedForMemoryPressure)
        XCTAssertNotNil(pages.activePage)
    }

    // MARK: - Split View presentation

    func testPreparingACardRefusesTabsOutsideTheSelectedSpace() throws {
        let split = makeSplitSession(memberCount: 2, selectedIndex: 0)
        let otherSpace = makeSpace(index: 21, savesCredentials: true)
        var withOther = split
        withOther.session.spaces.append(otherSpace)
        let pages = makeSplitPageStore(for: withOther)
        pages.select()

        XCTAssertNil(
            pages.prepareResidentPage(for: try XCTUnwrap(otherSpace.tabs.first?.id)),
            "A card only ever belongs to the selected Space."
        )
        XCTAssertNil(pages.prepareResidentPage(for: fixedUUID(0xDEAD)))
    }

    func testResidentPageAccessorRefusesNonMembersAndMismatchedAssignments() throws {
        let split = makeSplitSession(memberCount: 2, selectedIndex: 0)
        let space = try XCTUnwrap(split.session.spaces.first)
        let pages = makeSplitPageStore(for: split)
        pages.select()
        pages.prepareResidentPage(for: split.memberIDs[1])

        XCTAssertNotNil(
            pages.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: split.memberIDs[1],
                    spaceID: space.id,
                    profileID: space.profileID
                )
            )
        )
        XCTAssertNil(
            pages.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: split.memberIDs[1],
                    spaceID: space.id,
                    profileID: fixedUUID(0xBEEF)
                )
            ),
            """
            Binding a page across a profile boundary is exactly the isolation \
            failure per-Space browsing exists to prevent.
            """
        )
        XCTAssertNil(
            pages.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: split.nonMemberID,
                    spaceID: space.id,
                    profileID: space.profileID
                )
            ),
            "A background tab with a resident page is not a card."
        )
    }

    // MARK: - Helpers

    /// A Space holding one split run plus one ordinary background tab after it.
    private func makeSplitSession(
        memberCount: Int,
        selectedIndex: Int
    ) -> SplitFixture {
        let groupID = fixedUUID(0x5000)
        let members = (0..<memberCount).map { index in
            TabState.Seed(
                id: fixedUUID(0x5100 + index),
                title: "Card \(index)",
                url: URL(string: "https://cards.crest.test/\(index)"),
                placement: .current,
                splitGroupID: groupID,
                lastActivatedAt: fixedDate(index)
            )
        }
        let background = TabState.Seed(
            id: fixedUUID(0x5200),
            title: "Background",
            url: URL(string: "https://background.crest.test"),
            placement: .current,
            lastActivatedAt: fixedDate(0)
        )
        let space = SpaceState.Seed(
            id: fixedUUID(0x5300),
            profileID: fixedUUID(0x5400),
            name: "Split",
            symbol: "rectangle.split.2x1",
            accent: .indigo,
            folders: [],
            tabs: members + [background]
        )
        return SplitFixture(
            session: SessionState.Seed(spaces: [space]),
            spaceID: space.id,
            selectedID: members[selectedIndex].id,
            memberIDs: members.map(\.id),
            nonMemberID: background.id
        )
    }

    /// A scene over `split`'s session showing its selected card.
    private func makeSplitPageStore(for split: SplitFixture) -> MobileBrowserPageStore {
        MobileBrowserPageStore(
            browser: .hostingPages(split.session, showing: split.spaceID, tabs: [split.spaceID: split.selectedID]),
            usesEphemeralWebsiteDataStores: true)
    }

    private func fixedDate(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset))
    }

    private func makeSession(
        index: Int,
        savesCredentials: Bool = true
    ) -> SessionState.Seed {
        let space = makeSpace(index: index, savesCredentials: savesCredentials)
        return SessionState.Seed(spaces: [space])
    }

    private func makeSpace(
        index: Int,
        savesCredentials: Bool
    ) -> SpaceState.Seed {
        let tab = TabState.Seed.startPage(
            id: fixedUUID(index * 10 + 1),
            placement: .current
        )
        var credentialPreferences = CredentialPreferences.seeded
        credentialPreferences.isEnabled = savesCredentials
        return SpaceState.Seed(
            id: fixedUUID(index * 10 + 2),
            profileID: fixedUUID(index * 10 + 3),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            credentialPreferences: credentialPreferences
        )
    }

    private func submitMessage() throws -> BrowserCredentialFormMessage {
        try message([
            "version": 1,
            "event": "submit",
            "trusted": true,
            "formID": "login-form",
            "username": "person@example.com",
            "password": "secret-value",
            "passwordKind": "current",
        ])
    }

    private func documentStateMessage() throws -> BrowserCredentialFormMessage {
        try message([
            "version": 1,
            "event": "documentState",
            "trusted": true,
            "hasVisiblePasswordField": false,
        ])
    }

    private func message(_ body: [String: Any]) throws -> BrowserCredentialFormMessage {
        try XCTUnwrap(BrowserCredentialFormMessage(body: body))
    }

    private func waitUntil(
        timeout: Duration = .seconds(8),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the browser state to change.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func assertThrowsErrorAsync(
        _ expression: @autoclosure () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected the call to throw.", file: file, line: line)
        } catch {}
    }

    /// Crest Passwords turned off for a Space.
    private static let savingOff = CredentialPreferences(
        isEnabled: false, syncsCrestPasswordsWithICloud: false, alsoOffersSaveToSystemPasswords: false)

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}

/// One split run, its members in order, and the background tab that follows it.
private struct SplitFixture {
    var session: SessionState.Seed
    let spaceID: UUID
    let selectedID: UUID
    let memberIDs: [UUID]
    let nonMemberID: UUID
}
