import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserRootModelTests: XCTestCase {
    func testCompactSettingsActivationPresentsWithoutChangingTheSelectedPage() throws {
        let space = makeSpace(index: 10)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .compact)
        let selectedID = try XCTUnwrap(fixture.browser.shownTab?.id)
        let settingsID = try XCTUnwrap(fixture.browser.openSettings())
        fixture.browser.selectTab(selectedID)
        let before = fixture.browser.sessionSeed

        fixture.model.selectTab(settingsID)

        XCTAssertEqual(fixture.browser.sessionSeed, before)
        XCTAssertTrue(fixture.model.showsSettings)
    }

    func testRegularSettingsActivationsSelectTheirNativeTabAndRejectStaleAssignments() throws {
        var space = makeSpace(index: 20)
        let group = UUID()
        // A Start Page lists in no sidebar row, so the split pairs Settings
        // with a web page.
        var page = TabState.Seed(title: "Page", url: URL(string: "https://example.com/"), placement: .current)
        page.splitGroupID = group
        space.tabs = [page]
        var settings = TabState.Seed(title: "Settings", url: nil, nativeContent: .settings, placement: .current)
        settings.splitGroupID = group
        space.tabs.append(settings)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .regular)
        let assignment = BrowserTabRuntimeAssignment(
            tabID: settings.id, spaceID: space.id, profileID: space.profileID)
        XCTAssertTrue(fixture.model.presentSettings(matching: assignment))
        XCTAssertEqual(fixture.browser.shownTab?.id, settings.id)
        XCTAssertFalse(fixture.model.showsSettings)
        fixture.browser.selectTab(space.tabs[0].id)
        fixture.model.focusSplitCard(settings.id)
        XCTAssertEqual(fixture.browser.shownTab?.id, settings.id)
        XCTAssertFalse(fixture.model.showsSettings)
        let before = fixture.browser.sessionSeed
        XCTAssertFalse(
            fixture.model.presentSettings(
                matching: BrowserTabRuntimeAssignment(
                    tabID: settings.id, spaceID: space.id, profileID: UUID())))
        XCTAssertFalse(
            fixture.model.presentSettings(
                matching: BrowserTabRuntimeAssignment(
                    tabID: try XCTUnwrap(space.tabs.first?.id), spaceID: space.id, profileID: space.profileID)))
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        XCTAssertEqual(
            fixture.pages.nativeTabs.runtime(matching: assignment, content: .settings)?.assignment, assignment)
        XCTAssertNil(fixture.pages.residentPage(matching: assignment))
    }

    func testRestoredSettingsWaitsForMeasuredLayoutAndStaysSelectedAtRegularWidth() throws {
        let space = makeSpace(index: 10)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        let settings = try XCTUnwrap(fixture.browser.openSettings())
        XCTAssertFalse(fixture.model.routeSelectedSettingsAction())
        XCTAssertFalse(fixture.model.showsSettings)
        XCTAssertEqual(fixture.browser.shownTab?.id, settings)

        fixture.model.presentationChanged(to: .regular)

        XCTAssertFalse(fixture.model.routeSelectedSettingsAction())
        XCTAssertFalse(fixture.model.showsSettings)
        XCTAssertEqual(fixture.browser.shownTab?.id, settings)
        fixture.browser.selectTab(space.tabs[0].id)
        fixture.model.selectTab(settings)
        XCTAssertEqual(fixture.browser.shownTab?.id, settings)
        XCTAssertFalse(fixture.model.showsSettings)
    }

    func testRestoredCompactSettingsSelectionPresentsAndKeepsTheTab() throws {
        let space = makeSpace(index: 10)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        let settings = try XCTUnwrap(fixture.browser.openSettings())
        fixture.model.presentationChanged(to: .compact)
        XCTAssertTrue(fixture.model.showsSettings)
        XCTAssertNotEqual(fixture.browser.shownTab?.id, settings)
        XCTAssertEqual(
            fixture.browser.shownSpace?.tabs.model(settings)?.nativeTabContent, .settings)
        fixture.browser.selectTab(settings)
        XCTAssertTrue(fixture.model.routeSelectedSettingsAction())
        XCTAssertNotEqual(fixture.browser.shownTab?.id, settings)
    }

    func testSettingsWidthTransitionsRetainTheRuntimeDestinationAndSearch() throws {
        let space = makeSpace(index: 10)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .regular)
        fixture.model.openSettings()
        let settingsID = try XCTUnwrap(fixture.browser.shownTab?.id)
        let state = fixture.model.settings.state
        state.selection = .privacy
        state.searchText = "permission"

        fixture.model.presentationChanged(to: .compact)

        XCTAssertTrue(fixture.model.showsSettings)
        XCTAssertNotEqual(fixture.browser.shownTab?.id, settingsID)
        XCTAssertTrue(fixture.model.settings.state === state)
        XCTAssertEqual(state.path, [.privacy])
        state.path = [.general]
        fixture.model.presentationChanged(to: .regular)
        XCTAssertFalse(fixture.model.showsSettings)
        XCTAssertEqual(fixture.browser.shownTab?.id, settingsID)
        XCTAssertTrue(fixture.model.settings.state === state)
        XCTAssertEqual(state.selection, .general)
        XCTAssertEqual(state.searchText, "permission")
        XCTAssertEqual(fixture.browser.shownSpace?.tabs.models.filter { $0.nativeTabContent == .settings }.count, 1)
    }

    func testCompactSettingsCommandPreservesThePageAndExpandsIntoTheSameSpace() throws {
        let space = makeSpace(index: 10)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .compact)
        let before = fixture.browser.sessionSeed
        fixture.model.openSettings()
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        XCTAssertTrue(fixture.model.showsSettings)
        fixture.model.settings.state.path = [.privacy]

        fixture.model.presentationChanged(to: .regular)
        XCTAssertEqual(fixture.browser.shownTab?.nativeTabContent, .settings)
        XCTAssertEqual(fixture.model.settings.state.selection, .privacy)
        XCTAssertFalse(fixture.model.showsSettings)
    }

    func testCompactReopeningInactiveSettingsRetainsItsPaneAndExplicitBackNavigation() throws {
        for opensFromTab in [false, true] {
            let space = makeSpace(index: 10)
            let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
            fixture.model.presentationChanged(to: .regular)
            fixture.model.openSettings()
            let settingsID = try XCTUnwrap(fixture.browser.shownTab?.id)
            let state = fixture.model.settings.state
            state.selection = .privacy
            fixture.model.selectTab(space.tabs[0].id)
            fixture.model.presentationChanged(to: .compact)
            if opensFromTab {
                fixture.model.selectTab(settingsID)
            } else {
                fixture.model.openSettings()
            }
            XCTAssertTrue(fixture.model.showsSettings)
            XCTAssertTrue(fixture.model.settings.state === state)
            XCTAssertEqual(state.path, [.privacy])
            state.path = []
            fixture.model.showsSettings = false
            fixture.model.openSettings()
            XCTAssertTrue(fixture.model.settings.state === state)
            XCTAssertTrue(state.path.isEmpty)
        }
    }

    func testSettingsSheetCannotOpenACanvasInAnotherSpaceAfterResizing() {
        let first = makeSpace(index: 10)
        let second = makeSpace(index: 11)
        let fixture = makeFixture(spaces: [first, second], selectedSpaceID: first.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .compact)
        fixture.model.openSettings()
        fixture.browser.selectSpace(second.id)
        let before = fixture.browser.sessionSeed
        fixture.model.presentationChanged(to: .regular)
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        XCTAssertFalse(fixture.model.showsSettings)
    }

    func testSettingsSheetDiscardsStateWhenItsSpaceLocksOrProfileChanges() async throws {
        var space = makeSpace(index: 10)
        space.settings.accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(authenticator: MobileRootDeviceAuthenticator())
        let fixture = makeFixture(
            spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab, spaceAccess: access)
        let unlocked = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(space.id)))
        XCTAssertTrue(unlocked)
        fixture.model.presentationChanged(to: .compact)
        fixture.model.openSettings()
        let firstState = fixture.model.settings.state
        firstState.searchText = "private"
        access.lock(space.id)
        fixture.model.settings.reconcile()
        XCTAssertFalse(fixture.model.showsSettings)
        XCTAssertFalse(fixture.model.settings.state === firstState)
        XCTAssertTrue(fixture.model.settings.state.searchText.isEmpty)

        let ordinary = makeSpace(index: 20)
        let other = makeFixture(spaces: [ordinary], selectedSpaceID: ordinary.id, startupBehavior: .lastActiveTab)
        other.model.presentationChanged(to: .compact)
        other.model.openSettings()
        let previousState = other.model.settings.state
        other.browser.replaceProfileForTesting(of: ordinary.id, with: fixedUUID(999))
        other.model.settings.reconcile()
        XCTAssertFalse(other.model.showsSettings)
        XCTAssertFalse(other.model.settings.state === previousState)
    }

    func testRegularPaletteSelectionKeepsSettingsOwnedByItsSourceSpace() throws {
        var space = makeSpace(index: 10)
        let settings = TabState.Seed(title: "Settings", url: nil, nativeContent: .settings, placement: .current)
        space.tabs.append(settings)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .regular)
        let source = BrowserTabRuntimeAssignment(
            tabID: try XCTUnwrap(space.tabs.first?.id), spaceID: space.id, profileID: space.profileID)
        let target = BrowserTabRuntimeAssignment(tabID: settings.id, spaceID: space.id, profileID: space.profileID)
        XCTAssertTrue(fixture.model.selectPaletteTab(from: source, to: target))
        XCTAssertEqual(fixture.browser.shownSpace?.id, space.id)
        XCTAssertEqual(fixture.browser.shownTab?.id, settings.id)
        XCTAssertFalse(fixture.model.showsSettings)
        XCTAssertNotNil(fixture.pages.nativeTabs.runtime(matching: target, content: .settings))
    }

    func testLiveSettingsSpaceSelectionAcceptsAnUnfocusedSplitAndRejectsItsStaleCallback() throws {
        var source = makeSpace(index: 10)
        let destination = makeSpace(index: 20)
        let group = UUID()
        source.tabs[0].splitGroupID = group
        var settings = TabState.Seed(title: "Settings", url: nil, nativeContent: .settings, placement: .current)
        settings.splitGroupID = group
        source.tabs.append(settings)
        let fixture = makeFixture(
            spaces: [source, destination], selectedSpaceID: source.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .regular)
        let assignment = BrowserTabRuntimeAssignment(
            tabID: settings.id, spaceID: source.id, profileID: source.profileID)
        XCTAssertNotEqual(fixture.browser.shownTab?.id, settings.id)
        XCTAssertTrue(fixture.model.settings.selectLiveSpace(destination.id, matching: assignment))
        XCTAssertEqual(fixture.browser.shownSpace?.id, destination.id)
        XCTAssertEqual(fixture.browser.shownTab?.nativeTabContent, .settings)
        XCTAssertEqual(fixture.model.settings.state.selection, .spaces)
        let before = fixture.browser.sessionSeed
        XCTAssertFalse(fixture.model.settings.selectLiveSpace(source.id, matching: assignment))
        XCTAssertEqual(fixture.browser.sessionSeed, before)
    }

    func testLiveSettingsSpaceSelectionRejectsCompactPresentation() {
        var source = makeSpace(index: 10)
        let destination = makeSpace(index: 20)
        let settings = TabState.Seed(title: "Settings", url: nil, nativeContent: .settings, placement: .current)
        source.tabs.append(settings)
        let fixture = makeFixture(
            spaces: [source, destination], selectedSpaceID: source.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .compact)
        let assignment = BrowserTabRuntimeAssignment(
            tabID: settings.id, spaceID: source.id, profileID: source.profileID)
        let before = fixture.browser.sessionSeed

        XCTAssertFalse(fixture.model.settings.selectLiveSpace(destination.id, matching: assignment))
        XCTAssertEqual(fixture.browser.sessionSeed, before)
    }

    func testSettingsActionsRejectLockedAndForeignTargets() throws {
        let settings = TabState.Seed(title: "Settings", url: nil, nativeContent: .settings, placement: .current)
        var protectedSpace = makeSpace(index: 80)
        protectedSpace.settings.accessPolicy = .deviceOwnerAuthentication
        protectedSpace.tabs.append(settings)
        let otherSpace = makeSpace(index: 81)
        let access = BrowserSpaceAccessController()
        let fixture = makeFixture(
            spaces: [protectedSpace, otherSpace], selectedSpaceID: protectedSpace.id,
            startupBehavior: .lastActiveTab, spaceAccess: access)
        access.lock(protectedSpace.id)
        let before = fixture.browser.sessionSeed
        fixture.model.selectTab(settings.id)
        XCTAssertFalse(fixture.model.showsSettings)
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        fixture.browser.selectTab(settings.id)
        XCTAssertFalse(fixture.model.routeSelectedSettingsAction())
        XCTAssertFalse(fixture.model.showsSettings)
        fixture.browser.selectSpace(otherSpace.id)
        let foreignBefore = fixture.browser.sessionSeed
        fixture.model.selectTab(settings.id)
        XCTAssertFalse(fixture.model.showsSettings)
        XCTAssertEqual(fixture.browser.sessionSeed, foreignBefore)
        let source = BrowserTabRuntimeAssignment(
            tabID: try XCTUnwrap(otherSpace.tabs.first?.id), spaceID: otherSpace.id, profileID: otherSpace.profileID)
        let target = BrowserTabRuntimeAssignment(
            tabID: settings.id, spaceID: protectedSpace.id, profileID: protectedSpace.profileID)
        XCTAssertFalse(fixture.model.presentSettings(matching: target))
        XCTAssertFalse(fixture.model.selectPaletteTab(from: source, to: target))
        XCTAssertFalse(fixture.model.showsSettings)
    }

    func testSelectionChangeClassifiesRevisionTabSpaceAndProfileTransitions() {
        let firstSpaceID = fixedUUID(1)
        let secondSpaceID = fixedUUID(2)
        let firstProfileID = fixedUUID(3)
        let secondProfileID = fixedUUID(4)
        let firstTabID = fixedUUID(5)
        let secondTabID = fixedUUID(6)
        let original = selectionSnapshot(
            revision: 1,
            tabID: firstTabID,
            spaceID: firstSpaceID,
            profileID: firstProfileID
        )

        XCTAssertEqual(
            MobileBrowserRootSelectionChange.resolve(
                from: original,
                to: selectionSnapshot(
                    revision: 2,
                    tabID: firstTabID,
                    spaceID: firstSpaceID,
                    profileID: firstProfileID
                )
            ),
            .unchanged
        )
        XCTAssertEqual(
            MobileBrowserRootSelectionChange.resolve(
                from: original,
                to: selectionSnapshot(
                    revision: 2,
                    tabID: secondTabID,
                    spaceID: firstSpaceID,
                    profileID: firstProfileID
                )
            ),
            .tab
        )
        XCTAssertEqual(
            MobileBrowserRootSelectionChange.resolve(
                from: original,
                to: selectionSnapshot(
                    revision: 2,
                    tabID: secondTabID,
                    spaceID: secondSpaceID,
                    profileID: secondProfileID
                )
            ),
            .space
        )
        XCTAssertEqual(
            MobileBrowserRootSelectionChange.resolve(
                from: original,
                to: selectionSnapshot(
                    revision: 2,
                    tabID: firstTabID,
                    spaceID: firstSpaceID,
                    profileID: secondProfileID
                )
            ),
            .profile
        )
    }

    func testSelectionSynchronizationNeverCrossesSpaceOrProfileOwnership() async throws {
        let firstSpace = makeSpace(index: 10)
        let secondSpace = makeSpace(index: 20)
        let fixture = makeFixture(
            spaces: [firstSpace, secondSpace],
            selectedSpaceID: firstSpace.id,
            startupBehavior: .lastActiveTab
        )
        fixture.model.presentationChanged(to: .regular)
        await fixture.model.prepareBrowser()

        XCTAssertEqual(fixture.pages.activePage?.spaceID, firstSpace.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, firstSpace.profileID)

        let beforeSpaceChange = fixture.model.selectionSnapshot
        fixture.browser.selectSpace(secondSpace.id)
        let afterSpaceChange = fixture.model.selectionSnapshot
        XCTAssertTrue(
            fixture.model.synchronizeSelection(
                from: beforeSpaceChange,
                to: afterSpaceChange
            )
        )
        XCTAssertEqual(fixture.pages.activePage?.spaceID, secondSpace.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, secondSpace.profileID)
        XCTAssertTrue(
            fixture.pages.containsResidentPage(
                for: try XCTUnwrap(firstSpace.tabs.first?.id)
            )
        )
    }

    func testProfileRevisionBeforePreparationUsesOnlyTheCurrentProfile() async throws {
        let originalSpace = makeSpace(index: 22)
        let fixture = makeFixture(
            spaces: [originalSpace],
            selectedSpaceID: originalSpace.id,
            startupBehavior: .lastActiveTab
        )
        fixture.model.presentationChanged(to: .regular)
        let replacementProfile = BrowsingProfile(id: fixedUUID(99))
        let beforeProfileChange = fixture.model.selectionSnapshot
        fixture.browser.replaceProfileForTesting(of: originalSpace.id, with: replacementProfile.id)
        let afterProfileChange = fixture.model.selectionSnapshot

        XCTAssertEqual(
            MobileBrowserRootSelectionChange.resolve(
                from: beforeProfileChange,
                to: afterProfileChange
            ),
            .profile
        )
        XCTAssertFalse(
            fixture.model.synchronizeSelection(
                from: beforeProfileChange,
                to: afterProfileChange
            )
        )
        XCTAssertNil(fixture.pages.activePage)

        await fixture.model.prepareBrowser()

        XCTAssertEqual(fixture.pages.activePage?.spaceID, originalSpace.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, replacementProfile.id)
    }

    func testSelectionWaitsForLifecyclePreparationThenActivatesTheCurrentAssignment()
        async throws
    {
        var space = makeSpace(index: 25)
        let deferredTab = TabState.Seed(
            id: fixedUUID(254),
            title: "Deferred",
            url: URL(string: "https://example.com/deferred"),
            placement: .current
        )
        space.tabs.append(deferredTab)
        let fixture = makeFixture(
            spaces: [space],
            selectedSpaceID: space.id,
            startupBehavior: .lastActiveTab
        )
        fixture.model.presentationChanged(to: .regular)

        let beforeSelection = fixture.model.selectionSnapshot
        fixture.browser.selectTab(deferredTab.id)
        let afterSelection = fixture.model.selectionSnapshot

        XCTAssertFalse(
            fixture.model.synchronizeSelection(
                from: beforeSelection,
                to: afterSelection
            )
        )
        XCTAssertNil(fixture.pages.activePage)
        XCTAssertFalse(fixture.model.hasPreparedBrowser)

        await fixture.model.prepareBrowser()

        XCTAssertTrue(fixture.model.hasPreparedBrowser)
        XCTAssertEqual(fixture.pages.activePage?.tabID, deferredTab.id)
        XCTAssertEqual(fixture.pages.activePage?.spaceID, space.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, space.profileID)
    }

    func testCommandSelectionDismissesPresentationBeforeSynchronizingAddress()
        async throws
    {
        var space = makeSpace(index: 27)
        let destinationURL = try XCTUnwrap(
            URL(string: "https://example.com/command-destination")
        )
        let destinationTab = TabState.Seed(
            id: fixedUUID(274),
            title: "Command destination",
            url: destinationURL,
            placement: .current
        )
        space.tabs.append(destinationTab)
        let fixture = makeFixture(
            spaces: [space],
            selectedSpaceID: space.id,
            startupBehavior: .lastActiveTab
        )
        fixture.model.presentationChanged(to: .regular)
        await fixture.model.prepareBrowser()
        var addressBeforeSynchronization: String?
        var selectedTabBeforeSynchronization: UUID?

        let selected = fixture.model.selectNextTabFromCommand {
            addressBeforeSynchronization = fixture.model.address
            selectedTabBeforeSynchronization = fixture.browser.shownTab?.id
        }

        XCTAssertTrue(selected)
        XCTAssertEqual(selectedTabBeforeSynchronization, destinationTab.id)
        XCTAssertEqual(addressBeforeSynchronization, "")
        XCTAssertEqual(fixture.model.address, destinationURL.absoluteString)
        XCTAssertEqual(fixture.pages.activePage?.tabID, destinationTab.id)
    }

    func testCompactAndRegularStartupPreserveSelectedPageResidency() async throws {
        let space = makeSpace(index: 30)
        let fixture = makeFixture(
            spaces: [space],
            selectedSpaceID: space.id,
            startupBehavior: .lastActiveTab
        )

        fixture.model.presentationChanged(to: .regular)
        await fixture.model.prepareBrowser()
        let activePage = try XCTUnwrap(fixture.pages.activePage)
        XCTAssertEqual(activePage.spaceID, space.id)
        XCTAssertFalse(fixture.navigation.defersPageActivation)

        fixture.model.presentationChanged(to: .compact)
        fixture.navigation.showTabViewer()
        XCTAssertTrue(fixture.navigation.defersPageActivation)
        XCTAssertTrue(fixture.pages.containsResidentPage(for: activePage.tabID))

        fixture.model.activateSelectedTab()
        XCTAssertTrue(try XCTUnwrap(fixture.pages.activePage) === activePage)
        XCTAssertTrue(fixture.navigation.compactShowsPage)
    }

    func testPrivateCompactStartupWaitsForSelectionAndUsesItsEphemeralProfile() async throws {
        let space = makeSpace(index: 40)
        let fixture = makeFixture(
            spaces: [space],
            selectedSpaceID: space.id,
            browsingMode: .privateBrowsing,
            startupBehavior: .showStartPage
        )
        fixture.model.presentationChanged(to: .compact)

        await fixture.model.prepareBrowser()

        XCTAssertNil(fixture.pages.activePage)
        XCTAssertTrue(fixture.navigation.defersPageActivation)

        fixture.model.activateSelectedTab()
        let page = try XCTUnwrap(fixture.pages.activePage)
        XCTAssertEqual(page.spaceID, space.id)
        XCTAssertEqual(page.profileID, space.profileID)
        XCTAssertFalse(page.webView.configuration.websiteDataStore.isPersistent)
    }

    func testUnlockDestinationKeepsCompactInViewerAndActivatesRegularPage() async throws {
        var protectedSpace = makeSpace(index: 50)
        protectedSpace.settings.accessPolicy = .deviceOwnerAuthentication
        let authenticator = MobileRootDeviceAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        let fixture = makeFixture(
            spaces: [protectedSpace],
            selectedSpaceID: protectedSpace.id,
            startupBehavior: .lastActiveTab,
            spaceAccess: access
        )
        fixture.model.presentationChanged(to: .compact)
        await fixture.model.prepareBrowser()
        let lockedCompact = fixture.model.lockSnapshot(presentation: .compact)
        fixture.model.synchronizeLockTransition(
            from: lockedCompact,
            to: lockedCompact
        )
        XCTAssertNil(fixture.pages.activePage)

        let compactUnlockSucceeded = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(protectedSpace.id)))
        XCTAssertTrue(compactUnlockSucceeded)
        let unlockedCompact = fixture.model.lockSnapshot(presentation: .compact)
        fixture.model.synchronizeLockTransition(
            from: lockedCompact,
            to: unlockedCompact
        )
        XCTAssertNil(fixture.pages.activePage)
        XCTAssertFalse(fixture.navigation.compactShowsPage)

        access.lock(protectedSpace.id)
        fixture.model.presentationChanged(to: .regular)
        let lockedRegular = fixture.model.lockSnapshot(presentation: .regular)
        fixture.model.synchronizeLockTransition(
            from: unlockedCompact,
            to: lockedRegular
        )
        XCTAssertNil(fixture.pages.activePage)

        let regularUnlockSucceeded = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(protectedSpace.id)))
        XCTAssertTrue(regularUnlockSucceeded)
        let unlockedRegular = fixture.model.lockSnapshot(presentation: .regular)
        fixture.model.synchronizeLockTransition(
            from: lockedRegular,
            to: unlockedRegular
        )
        XCTAssertEqual(fixture.pages.activePage?.spaceID, protectedSpace.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, protectedSpace.profileID)
    }

    func testFloatingPhoneLockAndUnlockPreserveTheSidebarMode() async throws {
        var protectedSpace = makeSpace(index: 51)
        protectedSpace.settings.accessPolicy = .deviceOwnerAuthentication
        let authenticator = MobileRootDeviceAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        let fixture = makeFixture(
            spaces: [protectedSpace],
            selectedSpaceID: protectedSpace.id,
            startupBehavior: .lastActiveTab,
            spaceAccess: access
        )
        let initialUnlockSucceeded = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(protectedSpace.id)))
        XCTAssertTrue(initialUnlockSucceeded)
        fixture.model.presentationChanged(to: .compact)
        await fixture.model.prepareBrowser()
        fixture.model.activateSelectedTab()
        fixture.navigation.completePagePresentation()
        fixture.navigation.toggleCompactSidebar()
        let originalPage = try XCTUnwrap(fixture.pages.activePage)
        let unlocked = fixture.model.lockSnapshot(presentation: .compact)

        access.lockAllForInactiveScene()
        fixture.model.relockProtectedSpaces(fixture.model.lockedSpaceIDs)
        let locked = fixture.model.lockSnapshot(presentation: .compact)
        fixture.model.synchronizeLockTransition(from: unlocked, to: locked)

        XCTAssertNil(fixture.pages.activePage)
        XCTAssertTrue(fixture.pages.containsResidentPage(for: originalPage.tabID))
        XCTAssertTrue(fixture.navigation.compactShowsPage)
        XCTAssertEqual(fixture.navigation.regularSidebarPresentation, .floating)

        let secondUnlockSucceeded = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(protectedSpace.id)))
        XCTAssertTrue(secondUnlockSucceeded)
        let unlockedAgain = fixture.model.lockSnapshot(presentation: .compact)
        fixture.model.synchronizeLockTransition(from: locked, to: unlockedAgain)

        XCTAssertEqual(fixture.pages.activePage?.spaceID, protectedSpace.id)
        XCTAssertTrue(fixture.pages.activePage === originalPage)
        XCTAssertTrue(fixture.navigation.compactShowsPage)
        XCTAssertEqual(fixture.navigation.regularSidebarPresentation, .floating)
    }

    func testLockImmediatelyRevokesRetainedPageActionsBeforeReconciliation() async throws {
        var space = makeSpace(index: 52)
        space.settings.accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(authenticator: MobileRootDeviceAuthenticator())
        let fixture = makeFixture(
            spaces: [space], selectedSpaceID: space.id,
            startupBehavior: .lastActiveTab, spaceAccess: access
        )
        let unlocked = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(space.id)))
        XCTAssertTrue(unlocked)
        fixture.model.presentationChanged(to: .regular)
        await fixture.model.prepareBrowser()
        let page = try XCTUnwrap(fixture.model.selectedPage)
        let actions = try XCTUnwrap(fixture.model.selectedPageActions)
        XCTAssertTrue(actions.isAvailable)
        let session = fixture.browser.sessionSeed

        access.lock(space.id)
        actions.presentFind()
        fixture.model.synchronizePageMetadata(isAddressEditing: false)

        XCTAssertTrue(fixture.pages.activePage === page)
        XCTAssertNil(fixture.model.selectedPage)
        XCTAssertFalse(actions.isAvailable)
        XCTAssertNil(actions.pageAssignment)
        XCTAssertNil(actions.activeURL)
        XCTAssertFalse(page.isFindPresented)
        XCTAssertEqual(fixture.browser.sessionSeed, session)

        let unlockedAgain = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(space.id)))
        XCTAssertTrue(unlockedAgain)
        XCTAssertTrue(actions.isAvailable)
        XCTAssertTrue(actions.activePage === page)
    }

    func testPaletteActionsRejectStaleProfilesAndSelectExactDestinations() throws {
        var source = makeSpace(index: 60)
        let targetTab = TabState.Seed(title: "Destination", url: URL(string: "about:blank"), placement: .current)
        source.tabs.append(targetTab)
        let otherSpace = makeSpace(index: 70)
        let fixture = makeFixture(
            spaces: [source, otherSpace],
            selectedSpaceID: source.id,
            startupBehavior: .showStartPage
        )
        let sourceAssignment = BrowserTabRuntimeAssignment(
            tabID: try XCTUnwrap(source.tabs.first?.id),
            spaceID: source.id,
            profileID: source.profileID
        )
        let destinationAssignment = BrowserTabRuntimeAssignment(
            tabID: targetTab.id,
            spaceID: source.id,
            profileID: source.profileID
        )
        let foreignAssignment = BrowserTabRuntimeAssignment(
            tabID: try XCTUnwrap(otherSpace.tabs.first?.id),
            spaceID: otherSpace.id,
            profileID: otherSpace.profileID
        )

        XCTAssertFalse(fixture.model.selectPaletteTab(from: sourceAssignment, to: foreignAssignment))
        XCTAssertEqual(fixture.browser.shownSpace?.id, source.id)
        XCTAssertTrue(fixture.model.selectPaletteTab(from: sourceAssignment, to: destinationAssignment))
        XCTAssertEqual(fixture.browser.shownTab?.id, targetTab.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, source.profileID)

        fixture.browser.replaceProfileForTesting(of: source.id, with: fixedUUID(0xFE))
        let replacementURL = fixture.browser.shownTab?.address

        XCTAssertFalse(
            fixture.model.openPaletteURL(
                URL(fileURLWithPath: "/stale-palette-navigation"),
                mode: .editLocation(""),
                from: sourceAssignment
            )
        )
        XCTAssertEqual(fixture.browser.shownTab?.address, replacementURL)
        XCTAssertFalse(fixture.model.selectPaletteTab(from: sourceAssignment, to: destinationAssignment))
        XCTAssertEqual(fixture.browser.shownSpace?.profileID, fixedUUID(0xFE))
    }

    private func makeFixture(
        spaces: [SpaceState.Seed],
        selectedSpaceID: UUID,
        browsingMode: BrowserBrowsingMode = .standard,
        startupBehavior: StartupBehavior,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController()
    ) -> MobileBrowserRootFixture {
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: spaces),
            showing: selectedSpaceID,
            // Every Space shows its first tab, as a window restoring them would.
            tabs: Dictionary(
                uniqueKeysWithValues: spaces.compactMap { space in space.tabs.first.map { (space.id, $0.id) } }),
            browsingMode: browsingMode,
            core: .hostingPages(contentRuleLists: EmptyMobileRootContentRuleListProvider())
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: true
        )
        let navigation = MobileBrowserNavigationState()
        browser.attachSpaceAccess(spaceAccess)
        let model = MobileBrowserRootModel(
            browser: browser,
            pages: pages,
            navigation: navigation,
            spaceAccess: spaceAccess,
            windowState: nil,
            startupBehavior: startupBehavior,
            persistedSidebarWidth: MobileBrowserRootLayout.defaultRegularSidebarWidth
        )
        return MobileBrowserRootFixture(
            browser: browser,
            pages: pages,
            navigation: navigation,
            model: model
        )
    }

    private func makeSpace(index: Int) -> SpaceState.Seed {
        let tab = TabState.Seed.startPage(
            id: fixedUUID(index * 10 + 1),
            placement: .current
        )
        return SpaceState.Seed(
            id: fixedUUID(index * 10 + 2),
            profileID: fixedUUID(index * 10 + 3),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }

    private func selectionSnapshot(
        revision: Int,
        tabID: UUID,
        spaceID: UUID,
        profileID: UUID
    ) -> MobileBrowserRootSelectionSnapshot {
        MobileBrowserRootSelectionSnapshot(
            sessionRevision: BrowserSessionRevision(session: UInt64(revision), window: 0),
            selectedSpaceID: spaceID,
            selectedProfileID: profileID,
            assignment: BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: spaceID,
                profileID: profileID
            )
        )
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012x",
                value
            )
        )!
    }
}

@MainActor
private struct MobileBrowserRootFixture {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let model: MobileBrowserRootModel
}

@MainActor
private final class EmptyMobileRootContentRuleListProvider:
    BrowserContentRuleListProviding
{
    func balancedRuleLists() async throws -> [WKContentRuleList] { [] }
}

@MainActor
private final class MobileRootDeviceAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason: String) async throws -> Bool { true }
}
