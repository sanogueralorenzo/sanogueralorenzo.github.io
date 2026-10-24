import Foundation
import XCTest

@testable import Crest

/// The geometry that puts a fill prompt under the field that asked for it: what
/// the page is allowed to say about where its field is, what the page state
/// does with it, and where the panel lands once it knows.
@MainActor
final class BrowserCredentialFieldAnchorTests: XCTestCase {
    func testFieldGeometryContractCarriesARectAndNothingElse() throws {
        let moved = try XCTUnwrap(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "fieldGeometry",
                    "trusted": false,
                    "formID": "form-1",
                    "fieldRect": ["x": 40, "y": 320, "width": 220, "height": 32],
                ]
            )
        )
        XCTAssertEqual(moved.fieldRect?.x, 40)
        XCTAssertEqual(moved.fieldRect?.y, 320)
        XCTAssertEqual(moved.fieldRect?.width, 220)
        XCTAssertEqual(moved.fieldRect?.height, 32)
        XCTAssertNil(moved.password)

        XCTAssertNil(
            BrowserCredentialFormMessage(
                body: ["version": 1, "event": "fieldGeometry", "formID": "form-1"]
            )
        )
        XCTAssertNil(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "fieldGeometry",
                    "fieldRect": ["x": 40, "y": 320, "width": 220, "height": 32],
                ]
            )
        )
        XCTAssertNil(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "fieldGeometry",
                    "formID": "form-1",
                    "fieldRect": ["x": 40, "y": 320, "width": 220, "height": 32],
                    "password": "must-not-ride-along",
                ]
            )
        )
        XCTAssertNil(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "fieldGeometry",
                    "formID": "form-1",
                    "fieldRect": ["x": 40, "y": 320, "width": 220, "height": 32],
                    "username": "must-not-ride-along",
                ]
            )
        )
    }

    func testOnlyAMainFrameFieldAnchorsItsPromptAndOnlyItsOwnFormMovesIt() throws {
        let spaceID = UUID()
        let loginOrigin = try origin("https://accounts.example.com/login")
        let framedOrigin = try origin("https://embedded.example.com/login")
        let state = BrowserCredentialPageState<String>(spaceID: spaceID, core: CrestCore())

        state.receive(
            try focusMessage(formID: "login-form", x: 40, y: 300),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        let request = try XCTUnwrap(state.fillRequest)
        XCTAssertEqual(request.fieldRect?.y, 300)

        // Another form's report, and a report from another origin, are about
        // some other field entirely.
        state.receive(
            try geometryMessage(formID: "other-form", y: 10),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        state.receive(
            try geometryMessage(formID: "login-form", y: 20),
            frameOrigin: framedOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        // A subframe's coordinates say nothing about where the page is.
        state.receive(
            try geometryMessage(formID: "login-form", y: 30),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: false,
            fillTarget: "sub-frame"
        )
        XCTAssertEqual(state.fillRequest, request)

        state.receive(
            try geometryMessage(formID: "login-form", y: 120),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        let followed = try XCTUnwrap(state.fillRequest)
        XCTAssertEqual(followed.fieldRect?.y, 120)
        XCTAssertEqual(followed.id, request.id, "Following a field must not re-arm the request.")
        XCTAssertEqual(followed.requestedAt, request.requestedAt)

        // A frame's own rect is never taken for the page's.
        let framed = BrowserCredentialPageState<String>(spaceID: spaceID, core: CrestCore())
        framed.receive(
            try focusMessage(formID: "framed-form", x: 8, y: 12),
            frameOrigin: framedOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: false,
            fillTarget: "sub-frame"
        )
        XCTAssertNotNil(framed.fillRequest)
        XCTAssertNil(framed.fillRequest?.fieldRect)
    }

    func testDismissingAPromptStopsItsFieldFromBeingFollowed() throws {
        let loginOrigin = try origin("https://accounts.example.com/login")
        let state = BrowserCredentialPageState<String>(spaceID: UUID(), core: CrestCore())
        state.receive(
            try focusMessage(formID: "login-form", x: 40, y: 300),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        state.dismissFillRequest()

        state.receive(
            try geometryMessage(formID: "login-form", y: 120),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        XCTAssertNil(state.fillRequest)
    }

    // MARK: - Fixtures

    private func origin(_ string: String) throws -> CredentialOrigin {
        try XCTUnwrap(CredentialOrigin(url: XCTUnwrap(URL(string: string))))
    }

    private func focusMessage(
        formID: String,
        x: Double,
        y: Double
    ) throws -> BrowserCredentialFormMessage {
        try XCTUnwrap(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "focus",
                    "trusted": true,
                    "formID": formID,
                    "passwordKind": "current",
                    "fieldRect": ["x": x, "y": y, "width": 220, "height": 32],
                ]
            )
        )
    }

    private func geometryMessage(
        formID: String,
        y: Double
    ) throws -> BrowserCredentialFormMessage {
        try XCTUnwrap(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "fieldGeometry",
                    "formID": formID,
                    "fieldRect": ["x": 40, "y": y, "width": 220, "height": 32],
                ]
            )
        )
    }
}
