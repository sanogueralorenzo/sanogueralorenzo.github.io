import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialOperationModelTests: XCTestCase {
    func testNewerSuggestionRequestWinsWhenCancelledLoaderFinishesLast() async throws {
        let spaceID = UUID()
        let firstOrigin = try origin("https://first.example.com/login")
        let secondOrigin = try origin("https://second.example.com/login")
        let firstRequest = makeRequest(origin: firstOrigin)
        let secondRequest = makeRequest(origin: secondOrigin)
        let firstSuggestion = descriptor(
            username: "first@example.com",
            origin: firstOrigin,
            spaceID: spaceID
        )
        let secondSuggestion = descriptor(
            username: "second@example.com",
            origin: secondOrigin,
            spaceID: spaceID
        )
        let loader = SuspendedCredentialSuggestionLoader()
        let model = BrowserCredentialSuggestionModel()

        let firstLoad = Task { @MainActor in
            await model.load(firstRequest, in: spaceID, using: loader)
        }
        await loader.waitUntilRequestCountIs(1)
        let secondLoad = Task { @MainActor in
            await model.load(secondRequest, in: spaceID, using: loader)
        }
        await loader.waitUntilRequestCountIs(2)

        loader.succeed(origin: secondOrigin, with: [secondSuggestion])
        await secondLoad.value
        XCTAssertEqual(model.phase, .suggestions([secondSuggestion]))

        loader.succeed(origin: firstOrigin, with: [firstSuggestion])
        await firstLoad.value

        XCTAssertEqual(model.phase, .suggestions([secondSuggestion]))
        XCTAssertEqual(loader.cancelledOrigins, [firstOrigin])
    }

    func testCancellingSuggestionLoadPreventsLatePublication() async throws {
        let spaceID = UUID()
        let requestOrigin = try origin("https://cancelled.example.com/login")
        let request = makeRequest(origin: requestOrigin)
        let suggestion = descriptor(
            username: "cancelled@example.com",
            origin: requestOrigin,
            spaceID: spaceID
        )
        let loader = SuspendedCredentialSuggestionLoader()
        let model = BrowserCredentialSuggestionModel()
        let load = Task { @MainActor in
            await model.load(request, in: spaceID, using: loader)
        }
        await loader.waitUntilRequestCountIs(1)

        model.cancel()
        loader.succeed(origin: requestOrigin, with: [suggestion])
        await load.value

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(loader.cancelledOrigins, [requestOrigin])
    }

    func testStrongPasswordOperationSavesBeforeFillingGeneratedPassword() async {
        let model = BrowserStrongPasswordOperationModel()
        var operations: [String] = []

        await model.generateSaveAndFill(
            generate: { "fixed-strong-password" },
            save: { password in operations.append("save:\(password)") },
            fill: { password in operations.append("fill:\(password)") }
        )

        XCTAssertEqual(
            operations,
            [
                "save:fixed-strong-password",
                "fill:fixed-strong-password",
            ]
        )
        XCTAssertEqual(model.phase, .idle)
    }

    func testStrongPasswordOperationDoesNotFillWhenSavingFails() async {
        let model = BrowserStrongPasswordOperationModel()
        var filled = false

        await model.generateSaveAndFill(
            generate: { "fixed-strong-password" },
            save: { _ in throw TestFailure.expected },
            fill: { _ in filled = true }
        )

        XCTAssertFalse(filled)
        XCTAssertEqual(model.phase, .failedBeforeSave)
    }

    private func origin(_ string: String) throws -> CredentialOrigin {
        try XCTUnwrap(CredentialOrigin(url: try XCTUnwrap(URL(string: string))))
    }

    private func makeRequest(
        origin: CredentialOrigin,
        usernameHint: String? = nil
    ) -> BrowserCredentialFillRequest {
        BrowserCredentialFillRequest(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            usernameHint: usernameHint,
            passwordKind: .current,
            isCrossOriginFrame: false,
            requestedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func descriptor(
        username: String,
        origin: CredentialOrigin,
        spaceID: UUID
    ) -> CredentialDescriptor {
        CredentialDescriptor(
            spaceID: spaceID,
            origin: origin,
            username: username,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

@MainActor
private final class SuspendedCredentialSuggestionLoader: BrowserCredentialSuggestionLoading {
    private(set) var cancelledOrigins: [CredentialOrigin] = []

    private var requestedOrigins: [CredentialOrigin] = []
    private var continuations: [CredentialOrigin: CheckedContinuation<[CredentialDescriptor], any Error>] = [:]

    func credentialSuggestions(
        for origin: CredentialOrigin,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        requestedOrigins.append(origin)
        let suggestions = try await withCheckedThrowingContinuation { continuation in
            continuations[origin] = continuation
        }
        if Task.isCancelled {
            cancelledOrigins.append(origin)
        }
        return suggestions
    }

    func waitUntilRequestCountIs(_ expectedCount: Int) async {
        while requestedOrigins.count < expectedCount {
            await Task.yield()
        }
    }

    func succeed(
        origin: CredentialOrigin,
        with suggestions: [CredentialDescriptor]
    ) {
        continuations.removeValue(forKey: origin)?.resume(returning: suggestions)
    }
}

private enum TestFailure: Error {
    case expected
}
