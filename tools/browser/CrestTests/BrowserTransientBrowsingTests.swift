import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserTransientBrowsingTests: XCTestCase {
    func testLinkPullCancelsWhenTheSourceRuntimeAssignmentChanges() throws {
        let tab = BrowserPageTab.transient(showing: try XCTUnwrap(URL(string: "https://example.com/source"))).state
        let spaceID = UUID()
        var source: BrowserPageNavigationContext? = BrowserPageNavigationContext(
            tab: tab, spaceID: spaceID, profileID: UUID())
        let coordinator = BrowserTransientBrowsingCoordinator()
        let handler = BrowserLinkPullHandler(context: { source }, handle: coordinator.handleLinkDrag)
        let sample = BrowserLinkPullSample(
            location: CGPoint(x: 0.4, y: 0.4), size: CGSize(width: 800, height: 600), time: 1)
        XCTAssertTrue(
            handler.begin(
                url: try XCTUnwrap(URL(string: "https://example.com/destination")), label: nil,
                origin: CGPoint(x: 0.2, y: 0.2), sample: sample))
        XCTAssertEqual(coordinator.peekPresentationPhase, .staged)

        source = BrowserPageNavigationContext(tab: tab, spaceID: spaceID, profileID: UUID())

        XCTAssertFalse(handler.validateSource())
        XCTAssertFalse(handler.isActive)
        XCTAssertNil(coordinator.peekRequest)
        handler.end(sample)
        XCTAssertNil(coordinator.peekRequest)
    }

    func testLinkPullReleaseCommitsOnlyInsideItsSourceWindow() throws {
        let source = BrowserPageNavigationContext(
            tab: BrowserPageTab.transient(showing: try XCTUnwrap(URL(string: "https://example.com/source"))).state,
            spaceID: UUID(), profileID: UUID())
        let coordinator = BrowserTransientBrowsingCoordinator()
        let handler = BrowserLinkPullHandler(context: { source }, handle: coordinator.handleLinkDrag)
        let url = try XCTUnwrap(URL(string: "https://example.com/destination"))
        let origin = CGPoint(x: 0.2, y: 0.2)
        let sample = BrowserLinkPullSample(
            location: CGPoint(x: 0.4, y: 0.4), size: CGSize(width: 800, height: 600), time: 1)
        XCTAssertTrue(handler.begin(url: url, label: nil, origin: origin, sample: sample))
        let request = try XCTUnwrap(coordinator.peekRequest)

        handler.end(BrowserLinkPullSample(location: sample.location, size: sample.size, time: 2))

        XCTAssertEqual(coordinator.peekRequest, request)
        XCTAssertEqual(coordinator.peekPresentationPhase, .committed)
        XCTAssertFalse(handler.isActive)
        handler.cancel()
        XCTAssertEqual(coordinator.peekRequest, request)

        XCTAssertTrue(handler.begin(url: url, label: nil, origin: origin, sample: sample))
        handler.end(
            BrowserLinkPullSample(
                location: CGPoint(x: 1.1, y: 0.4), size: sample.size, time: 2))

        XCTAssertNil(coordinator.peekRequest)
        XCTAssertFalse(handler.isActive)
    }

    func testPullReleaseRequiresDistanceAndRejectsVelocityBackTowardTheLink() {
        for translation in [CGSize(width: 80, height: 0), CGSize(width: -60, height: 80)] {
            XCTAssertTrue(BrowserPeekPullSession.opensPeek(translation: translation, velocity: translation))
            XCTAssertFalse(
                BrowserPeekPullSession.opensPeek(
                    translation: translation,
                    velocity: CGSize(width: -translation.width, height: -translation.height)))
            XCTAssertTrue(BrowserPeekPullSession.opensPeek(translation: translation, velocity: .zero))
        }
        XCTAssertFalse(
            BrowserPeekPullSession.opensPeek(
                translation: CGSize(width: 4, height: 3), velocity: CGSize(width: 900, height: 900)))
    }

    func testReturningPullStaysStagedAndLateUpdatesCannotReplaceAnotherPeek() throws {
        let request = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/pull")),
            sourceTabID: UUID(), sourceTitle: "Source",
            spaceAssignment: BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID()),
            trigger: .linkDrag)
        let coordinator = BrowserTransientBrowsingCoordinator()
        var state = BrowserPeekMotionState(
            origin: CGPoint(x: 0.2, y: 0.2),
            location: CGPoint(x: 0.4, y: 0.4), scale: 0.4)
        coordinator.beginPeekDrag(request, state: state)
        state.releasedAt = Date()
        state.returnsToSource = true
        coordinator.updatePeekDrag(id: request.id, state: state)
        XCTAssertEqual(coordinator.peekPresentationPhase, .staged)
        XCTAssertEqual(coordinator.peekRequest?.id, request.id)
        coordinator.cancelStagedPeek(id: request.id)
        XCTAssertNil(coordinator.peekMotionState)

        coordinator.beginPeekDrag(request, state: state)
        coordinator.presentPeek(request)
        let clickMotion = coordinator.peekMotionState
        coordinator.updatePeekDrag(id: request.id, state: state)
        XCTAssertNotNil(clickMotion?.releasedAt)
        XCTAssertEqual(coordinator.peekMotionState, clickMotion)
        XCTAssertEqual(coordinator.peekPresentationPhase, .committed)
        coordinator.cancelStagedPeek(id: request.id)
        XCTAssertEqual(coordinator.peekRequest?.id, request.id)
    }

    func testEmptyQuickWindowRequestStartsWithoutNavigating() {
        let request = BrowserQuickWindowRequest.empty(
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: UUID(),
                profileID: UUID()
            )
        )

        XCTAssertNil(request.initialURL)
    }

    func testQuickWindowPresentationIdentityFocusesAnExactURLInTheSameSpace() throws {
        let spaceID = UUID()
        let profileID = UUID()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        let first = BrowserQuickWindowRequest(
            url: url,
            spaceAssignment: assignment
        )
        let duplicate = BrowserQuickWindowRequest(
            url: url,
            spaceAssignment: assignment
        )

        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(Set([first, duplicate]).count, 1)
        XCTAssertNotEqual(
            first,
            BrowserQuickWindowRequest(
                url: url,
                spaceAssignment: BrowserSpaceRuntimeAssignment(
                    spaceID: spaceID,
                    profileID: UUID()
                )
            )
        )
        XCTAssertNotEqual(
            BrowserQuickWindowRequest.empty(spaceAssignment: assignment),
            BrowserQuickWindowRequest.empty(spaceAssignment: assignment)
        )
        XCTAssertEqual(first.assignment.spaceID, spaceID)
        XCTAssertEqual(first.assignment.profileID, profileID)
    }

    func testQuickWindowCarriesPresentationOriginWithoutChangingWindowIdentity() throws {
        let spaceID = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        let targetWindowID = UUID()
        let source = BrowserPeekSourcePresentation(
            normalizedMinX: 0.12,
            normalizedMinY: 0.28,
            normalizedWidth: 0.34,
            normalizedHeight: 0.05,
            normalizedTouchX: 0.21,
            normalizedTouchY: 0.31,
            label: "External link"
        )
        let request = BrowserQuickWindowRequest(
            url: url,
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: UUID()
            ),
            targetWindowID: targetWindowID,
            sourcePresentation: source
        )
        let sameWindowWithoutSource = BrowserQuickWindowRequest(
            url: url,
            spaceAssignment: request.assignment
        )

        XCTAssertEqual(request.sourcePresentation, source)
        XCTAssertEqual(request.targetWindowID, targetWindowID)
        XCTAssertEqual(request, sameWindowWithoutSource)
        XCTAssertEqual(Set([request, sameWindowWithoutSource]).count, 1)
    }

    func testCoordinatorMatchesTheFullQuickWindowRequestBeyondPublicEquality() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: UUID(),
            profileID: UUID()
        )
        let first = BrowserQuickWindowRequest(
            id: UUID(),
            url: url,
            spaceAssignment: assignment,
            targetWindowID: UUID(),
            sourcePresentation: BrowserPeekSourcePresentation(
                normalizedMinX: 0.1,
                normalizedMinY: 0.2,
                normalizedWidth: 0.3,
                normalizedHeight: 0.04,
                label: "First"
            )
        )
        let equalityEquivalentReplacement = BrowserQuickWindowRequest(
            id: UUID(),
            url: url,
            spaceAssignment: assignment,
            targetWindowID: UUID(),
            sourcePresentation: nil
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentQuickWindow(first)

        XCTAssertEqual(first, equalityEquivalentReplacement)
        XCTAssertFalse(
            coordinator.isPresentingQuickWindow(equalityEquivalentReplacement)
        )
        XCTAssertFalse(
            coordinator.dismissQuickWindow(equalityEquivalentReplacement)
        )
        XCTAssertTrue(coordinator.isPresentingQuickWindow(first))
        XCTAssertEqual(coordinator.quickWindowRequest?.id, first.id)
    }

    func testDelayedPeekCommitCannotReplaceANewerTransientPresentation() throws {
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: UUID(),
            profileID: UUID()
        )
        let first = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/first")),
            sourceTabID: UUID(),
            sourceTitle: "First",
            spaceAssignment: assignment,
            trigger: .longPress
        )
        let second = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/second")),
            sourceTabID: UUID(),
            sourceTitle: "Second",
            spaceAssignment: assignment,
            trigger: .longPress
        )
        let quickWindow = BrowserQuickWindowRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/quick")),
            spaceAssignment: assignment
        )
        let coordinator = BrowserTransientBrowsingCoordinator()

        coordinator.stagePeek(first)
        coordinator.stagePeek(second)
        coordinator.commitPeek(first)

        XCTAssertEqual(coordinator.peekRequest, second)
        XCTAssertEqual(coordinator.peekPresentationPhase, .staged)

        coordinator.presentQuickWindow(quickWindow)
        coordinator.commitPeek(first)

        XCTAssertEqual(coordinator.quickWindowRequest, quickWindow)
        XCTAssertNil(coordinator.peekRequest)
        XCTAssertNil(coordinator.peekPresentationPhase)
    }

    func testRetargetingAQuickWindowRequestPreservesItsExactTargetWindowRuntime() throws {
        let source = BrowserPeekSourcePresentation(
            normalizedMinX: 0.12,
            normalizedMinY: 0.28,
            normalizedWidth: 0.34,
            normalizedHeight: 0.05,
            normalizedTouchX: 0.21,
            normalizedTouchY: 0.31,
            label: "External link"
        )
        let targetWindowID = UUID()
        let request = BrowserQuickWindowRequest(
            id: UUID(),
            url: try XCTUnwrap(URL(string: "https://example.com/original")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: UUID(),
                profileID: UUID()
            ),
            targetWindowID: targetWindowID,
            sourcePresentation: source
        )
        let replacementAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: UUID(),
            profileID: UUID()
        )

        let revised = request.retargeted(
            to: try XCTUnwrap(URL(string: "https://example.com/revised")),
            assignment: replacementAssignment
        )

        XCTAssertEqual(revised.id, request.id)
        XCTAssertEqual(revised.assignment, replacementAssignment)
        XCTAssertEqual(revised.targetWindowID, targetWindowID)
        XCTAssertEqual(revised.sourcePresentation, source)
    }

    func testTransientActivityClockCoalescesPublicationWithoutLosingExactActivity() {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = BrowserTransientActivityClock(
            now: start,
            publicationInterval: 15
        )

        clock.recordActivity(at: start.addingTimeInterval(5))
        XCTAssertEqual(clock.revision, 0)
        XCTAssertEqual(
            clock.inactivityRemaining(
                for: 60,
                at: start.addingTimeInterval(50)
            ),
            15
        )

        clock.recordActivity(at: start.addingTimeInterval(20))
        XCTAssertEqual(clock.revision, 1)
        clock.recordActivity(
            at: start.addingTimeInterval(21),
            restartsTimerImmediately: true
        )
        XCTAssertEqual(clock.revision, 2)
    }

    func testPeekSourcePresentationBoundsHostileWebContentGeometryAndLabels() {
        let source = BrowserPeekSourcePresentation(
            normalizedMinX: .nan,
            normalizedMinY: -.infinity,
            normalizedWidth: .infinity,
            normalizedHeight: 4,
            normalizedTouchX: 8,
            normalizedTouchY: -.infinity,
            label: String(repeating: "x", count: 1_000)
        )

        XCTAssertEqual(source.normalizedMinX, 0)
        XCTAssertEqual(source.normalizedMinY, 0)
        XCTAssertEqual(source.normalizedWidth, 0)
        XCTAssertEqual(source.normalizedHeight, 1)
        XCTAssertEqual(source.normalizedTouchX, 1)
        XCTAssertEqual(source.normalizedTouchY, 0)
        XCTAssertEqual(source.label.count, 160)
    }

    func testMovingTabIntoSavedAreaCapturesRootAndNavigationDoesNotReplaceIt() throws {
        let browser = BrowserStore(seed: .preview, core: .hostingPages())
        let destination = try XCTUnwrap(URL(string: "https://example.com/root"))
        let laterURL = try XCTUnwrap(URL(string: "https://example.net/later"))
        let tabID = try XCTUnwrap(browser.openNewTab(url: destination))

        XCTAssertTrue(browser.moveTab(tabID, to: .saved))
        let page = try XCTUnwrap(browser.openReportingPage(for: tabID))
        browser.finishNavigation(of: page, to: laterURL, titled: "Later")
        page.release(keepingState: false)

        let tab = try XCTUnwrap(browser.shownTab)
        XCTAssertEqual(tab.id, tabID)
        XCTAssertEqual(tab.address, laterURL)
        XCTAssertEqual(tab.savedURL, destination.absoluteString)
    }

    func testDismissedQuickWindowArchivesAndRecordsHistoryInExactSpace() throws {
        let browser = BrowserStore(seed: .preview, core: .hostingPages())
        let personal = try XCTUnwrap(browser.spaceModels.last)
        let work = try XCTUnwrap(browser.spaceModels.first)
        let url = try XCTUnwrap(URL(string: "https://example.com/transient"))

        let page = try XCTUnwrap(browser.openReportingPage(for: nil, in: personal.id))
        browser.finishNavigation(of: page, to: url, titled: "Transient")
        XCTAssertTrue(browser.archiveTransientPage(page.id, matching: BrowserSpaceRuntimeAssignment(space: personal)))
        page.release(keepingState: false)
        let session = browser.sessionSeed

        XCTAssertEqual(session.space(id: personal.id)?.archivedTabs.last?.reason, .quickWindow)
        XCTAssertEqual(session.space(id: personal.id)?.history.first?.url, url.absoluteString)
        XCTAssertFalse(session.space(id: work.id)?.history.contains(where: { $0.url == url.absoluteString }) == true)
    }

    func testTransientMutationsRejectAReplacementProfileWithTheSameSpaceID() throws {
        let source = try XCTUnwrap(BrowserStore(seed: .preview).shownSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: source)
        var replacement = source.value.seed
        replacement.profileID = UUID()
        replacement.history = []
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [replacement])
        )
        let url = try XCTUnwrap(URL(string: "https://example.com/stale-lease"))

        XCTAssertNil(browser.openNewTab(url: url, matching: assignment))
        XCTAssertFalse(browser.archiveTransientPage(UUID(), matching: assignment))
        XCTAssertTrue(browser.shownSpace?.history.entries.isEmpty == true)
        XCTAssertEqual(browser.shownSpace?.archive.entries.map(\.seed), replacement.archivedTabs)
    }

    // MARK: - The shared lease ladder

    func testTransientLeaseDispositionAnswersInLadderOrder() throws {
        let openSeed = makePolicySpace(name: "Work")
        var lockedSeed = makePolicySpace(name: "Private")
        lockedSeed.settings.accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [openSeed, lockedSeed]))
        let open = try XCTUnwrap(browser.spaceModel(openSeed.id))
        let locked = try XCTUnwrap(browser.spaceModel(lockedSeed.id))
        let access = makeAccessController()

        XCTAssertEqual(
            BrowserTransientLeaseDisposition(
                isPresentingRequest: false, space: locked, isLocked: access.isLocked),
            .notPresented
        )
        XCTAssertEqual(
            BrowserTransientLeaseDisposition(isPresentingRequest: true, space: nil, isLocked: access.isLocked),
            .sourceMissing
        )
        XCTAssertEqual(
            BrowserTransientLeaseDisposition(
                isPresentingRequest: true, space: locked, isLocked: access.isLocked),
            .sourceLocked
        )
        XCTAssertEqual(
            BrowserTransientLeaseDisposition(
                isPresentingRequest: true, space: open, isLocked: access.isLocked),
            .usable(open)
        )
    }

    func testTransientPromotionListsLiveSpacesAndTheRequestsOwnLockedSpace() {
        var lockedSource = makePolicySpace(name: "Source")
        lockedSource.settings.accessPolicy = .deviceOwnerAuthentication
        var lockedOther = makePolicySpace(name: "Private")
        lockedOther.settings.accessPolicy = .deviceOwnerAuthentication
        let open = makePolicySpace(name: "Work")
        let deleting = makePolicySpace(name: "Going")
        let access = makeAccessController()
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [lockedSource, lockedOther, open, deleting]))
        XCTAssertTrue(browser.family.beginDeletingSpace(deleting.id))
        defer { browser.family.finishDeletingSpace(deleting.id) }

        let offered = browser.transientSpaces(forRequestIn: lockedSource.id, isLocked: access.isLocked)

        XCTAssertEqual(offered.map(\.id), [lockedSource.id, open.id])
    }

    func testTransientLeaseIsReusedOnlyByItsRequestAssignment() throws {
        let space = makePolicySpace(name: "Source")
        let other = makePolicySpace(name: "Destination")
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space, other]), showing: space.id)
        let pool = BrowserPagePool(browser: browser)
        let lease = try XCTUnwrap(
            pool.makeTransientPageLease(
                url: try XCTUnwrap(URL(string: "about:blank")), in: try XCTUnwrap(browser.spaceModel(space.id)))
        )

        XCTAssertTrue(lease.isReusable(for: assignment))
        XCTAssertFalse(lease.isReusable(for: BrowserSpaceRuntimeAssignment(space: other)))
        lease.release()
        XCTAssertFalse(lease.isReusable(for: assignment))
    }

    private func makePolicySpace(name: String) -> SpaceState.Seed {
        let tab = TabState.Seed.startPage()
        return SpaceState.Seed(
            name: name,
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }

    private func makeAccessController() -> BrowserSpaceAccessController {
        BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
    }
}
