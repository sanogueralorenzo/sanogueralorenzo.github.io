import Foundation
import XCTest

@testable import Crest

@MainActor
final class NativeBrowserPromptTests: XCTestCase {
    private let origin = SiteOrigin(scheme: "https", host: "meet.example", port: 443)
    private let dialog = ScriptDialogQuestion(
        kind: .confirm, message: "Leave?", defaultText: "", sourceURL: "https://meet.example/")

    @MainActor
    private final class Context {
        let core: CrestCore
        let browser: BrowserStore
        let page: CorePage
        let webKit: WebKitEnginePage
        let binding: WebKitEngineBinding
        let spaceID: UUID
        var events: [any CorePromptChange] = []
        lazy var prompts = NativeBrowserPrompts(core: core) { [weak self] in self?.events.append($0) }
        init(directory: URL? = nil) throws {
            core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory?.path))
            core.engines.register(
                WebKitEngineBinding(
                    profileStores: WebKitBrowserWebsiteDataStoreRemover(), contentBlocking: WebKitContentBlocking()))
            binding = try XCTUnwrap(core.engines.webKit)
            browser = BrowserStore(
                seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "Test", tabs: [])]), core: core)
            spaceID = try XCTUnwrap(browser.spaceModels.first).id
            let opened = try XCTUnwrap(browser.openWebKitPage(in: spaceID, for: nil))
            page = opened.core
            webKit = opened.webKit
        }
        func request(
            _ permission: SitePermission, origin: SiteOrigin, id: UUID = UUID(),
            answer: @escaping @MainActor (Bool) -> Void
        ) -> UUID {
            binding.prompts[id] = WebKitPendingPermission(pageID: page.id, answer: answer)
            prompts.report(
                PermissionRequested(
                    promptID: id, pageID: page.id,
                    question: PermissionQuestion(permission: permission, origin: origin, topLevelOrigin: origin)),
                from: binding)
            return id
        }
    }

    func testSavedAndSessionAnswersSkipThePromptAndSystemPickerStillAsksEachTime() throws {
        let context = try Context()
        for permission in [SitePermission.location, .screenSharing] {
            for decision in SitePermissionDecision.all where !(permission.isAskedBySystem && decision.grants) {
                try context.core.send(
                    DecideSitePermission(
                        spaceID: context.spaceID, origin: origin, permission: permission, detail: nil,
                        decision: decision))
                context.events.removeAll()
                var answers: [Bool] = []
                let id = context.request(permission, origin: origin) { answers.append($0) }
                if decision.asks && !permission.isAskedBySystem {
                    XCTAssertEqual(context.events.count, 1)
                    XCTAssertTrue(answers.isEmpty)
                    context.prompts.withdraw(id, from: context.binding)
                    context.binding.prompts.removeValue(forKey: id)?.decline()
                } else {
                    XCTAssertTrue(context.events.isEmpty)
                    XCTAssertEqual(answers, [!decision.denies])
                    XCTAssertNil(context.binding.prompts[id])
                }
            }
        }
        XCTAssertThrowsError(
            try context.core.send(
                DecideSitePermission(
                    spaceID: context.spaceID, origin: origin, permission: .screenSharing, detail: nil,
                    decision: .grantPersistently)))
    }

    func testCombinedCaptureRespectsEitherDeviceBlockAndCombinedGrantAnswersSingleDevice() throws {
        let context = try Context()
        try context.core.send(
            DecideSitePermission(
                spaceID: context.spaceID, origin: origin, permission: .cameraAndMicrophone, detail: nil,
                decision: .grantPersistently))
        var answers: [Bool] = []
        _ = context.request(.camera, origin: origin) { answers.append($0) }
        try context.core.send(
            DecideSitePermission(
                spaceID: context.spaceID, origin: origin, permission: .microphone, detail: nil,
                decision: .denyForSession))
        _ = context.request(.cameraAndMicrophone, origin: origin) { answers.append($0) }
        XCTAssertEqual(answers, [true, false])
        XCTAssertTrue(context.events.isEmpty)
    }

    func testRememberedAnswerAndLaterBlockAreAppliedBeforeSettling() throws {
        let context = try Context()
        var answers: [Bool] = []
        let first = context.request(.location, origin: origin) { answers.append($0) }
        try context.prompts.send(AnswerPermission(promptID: first, grants: true, remembers: true))
        XCTAssertEqual(answers, [true])
        XCTAssertEqual(
            try context.core.query(
                SiteDecision(spaceID: context.spaceID, origin: origin, permission: .location, detail: nil)
            ).decision, .grantPersistently)
        XCTAssertEqual(context.events.compactMap { $0 as? PromptSettled }.map(\.promptID), [first])
        try context.core.send(ResetSpacePermissions(spaceID: context.spaceID))
        let second = context.request(.location, origin: origin) { answers.append($0) }
        try context.core.send(
            DecideSitePermission(
                spaceID: context.spaceID, origin: origin, permission: .location, detail: nil, decision: .denyForSession)
        )
        try context.prompts.send(AnswerPermission(promptID: second, grants: true, remembers: true))
        XCTAssertEqual(answers, [true, false])
        XCTAssertEqual(
            try context.core.query(
                SiteDecision(spaceID: context.spaceID, origin: origin, permission: .location, detail: nil)
            ).decision, .denyForSession)
        XCTAssertThrowsError(
            try context.prompts.send(AnswerPermission(promptID: second, grants: true, remembers: false)))
    }

    func testDuplicateReportsAndWrongAnswersDoNotSettleAnotherKindOfQuestion() throws {
        let context = try Context()
        let id = UUID()
        var answers: [Bool] = []
        context.binding.prompts[id] = WebKitPendingScriptDialog(pageID: context.page.id) { accepted, _ in
            answers.append(accepted)
        }
        let opened = ScriptDialogOpened(promptID: id, pageID: context.page.id, question: dialog)
        context.prompts.report(opened, from: context.binding)
        context.prompts.report(opened, from: context.binding)
        XCTAssertEqual(context.events.count, 1)
        XCTAssertThrowsError(try context.prompts.send(AnswerPermission(promptID: id, grants: true, remembers: false))) {
            XCTAssertEqual($0 as? NativeBrowserPrompts.Failure, .answerMismatch(id))
        }
        XCTAssertTrue(answers.isEmpty)
        try context.prompts.send(AnswerScriptDialog(promptID: id, accepted: true, text: "answer"))
        XCTAssertEqual(answers, [true])
        XCTAssertThrowsError(try context.prompts.send(AnswerScriptDialog(promptID: id, accepted: false, text: nil)))
        XCTAssertEqual(context.events.compactMap { $0 as? PromptSettled }.count, 1)
    }

    func testMissingPageDeclinesAndWithdrawalAndClosingRetireTheQuestionExactlyOnce() throws {
        let context = try Context()
        let unknownPage = UUID()
        let unknownPrompt = UUID()
        var answers: [Bool] = []
        context.binding.prompts[unknownPrompt] = WebKitPendingScriptDialog(pageID: unknownPage) { accepted, _ in
            answers.append(accepted)
        }
        context.prompts.report(
            ScriptDialogOpened(promptID: unknownPrompt, pageID: unknownPage, question: dialog), from: context.binding)
        XCTAssertEqual(answers, [false])
        XCTAssertTrue(context.events.isEmpty)
        let withdrawn = context.request(.location, origin: origin) { answers.append($0) }
        context.prompts.report(PromptWithdrawn(promptID: withdrawn), from: context.binding)
        context.prompts.report(PromptWithdrawn(promptID: withdrawn), from: context.binding)
        XCTAssertEqual(context.events.compactMap { $0 as? PromptSettled }.map(\.promptID), [withdrawn])
        XCTAssertThrowsError(
            try context.prompts.send(AnswerPermission(promptID: withdrawn, grants: true, remembers: false)))
        let closing = context.request(.location, origin: origin) { answers.append($0) }
        context.page.release(keepingState: false)
        context.core.drain()
        context.prompts.prune()
        context.prompts.prune()
        XCTAssertEqual(context.events.compactMap { $0 as? PromptSettled }.map(\.promptID), [withdrawn, closing])
        XCTAssertThrowsError(
            try context.prompts.send(AnswerPermission(promptID: closing, grants: true, remembers: false)))
    }

    func testCredentialPassesDirectlyToWebKitWithoutBeingPublishedLoggedOrSaved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secret = "correct-horse-7f3a9c"
        var changes: [any CoreChange] = []
        do {
            let context = try Context(directory: directory)
            context.core.batchApplied = { changes += $0 }
            let id = UUID()
            var received: AuthenticationCredential?
            context.binding.prompts[id] = WebKitPendingAuthentication(pageID: context.page.id) { received = $0 }
            let question = AuthenticationQuestion(
                url: "https://intranet.example/", host: "intranet.example", port: 443, realm: "Staff", scheme: .digest,
                isProxy: false, previousFailures: 1)
            context.prompts.report(
                AuthenticationChallenged(promptID: id, pageID: context.page.id, question: question),
                from: context.binding)
            let credential = AuthenticationCredential(username: "paul", password: secret)
            let answer = AnswerAuthentication(promptID: id, credential: credential)
            XCTAssertFalse(String(describing: answer).contains(secret))
            XCTAssertFalse(String(reflecting: answer).contains(secret))
            try context.prompts.send(answer)
            XCTAssertEqual(received, credential)
            XCTAssertFalse(String(describing: context.events).contains(secret))
            XCTAssertFalse(String(describing: changes).contains(secret))
        }
        for case let file as URL in FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
            ?? FileManager.default.enumerator(atPath: directory.path)!
        {
            guard let bytes = try? Data(contentsOf: file) else { continue }
            for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
                XCTAssertNil(bytes.range(of: try XCTUnwrap(secret.data(using: encoding))))
            }
        }
    }

    func testSavingAChoiceCannotWithdrawTheAnswerBeingCommitted() throws {
        let context = try Context()
        var answers: [Bool] = []
        let id = context.request(.location, origin: origin) { answers.append($0) }
        context.core.followSitePermissions(context) { [weak context] _ in context?.binding.withdraw(id) }
        try context.prompts.send(AnswerPermission(promptID: id, grants: true, remembers: true))
        XCTAssertEqual(answers, [true])
        XCTAssertEqual(context.events.compactMap { $0 as? PromptSettled }.map(\.promptID), [id])
    }

    func testReentrantWebKitRequestIsPresentedAfterThePreviousQuestionSettles() throws {
        let context = try Context()
        var next: UUID?
        let first = context.request(.location, origin: origin) { [origin] _ in
            next = context.request(.camera, origin: origin) { _ in }
        }
        try context.prompts.send(AnswerPermission(promptID: first, grants: true, remembers: false))
        XCTAssertEqual(context.events.count, 3)
        XCTAssertEqual((context.events[0] as? PermissionAsked)?.promptID, first)
        XCTAssertEqual((context.events[1] as? PromptSettled)?.promptID, first)
        XCTAssertEqual((context.events[2] as? PermissionAsked)?.promptID, next)
    }

    func testSavedAnswersDoNotRecursivelyEnterWebKitCallbacks() throws {
        let context = try Context()
        try context.core.send(
            DecideSitePermission(
                spaceID: context.spaceID, origin: origin, permission: .location, detail: nil,
                decision: .grantPersistently))
        var count = 0
        var depth = 0
        var maximumDepth = 0
        func askAgain() {
            _ = context.request(.location, origin: origin) { allowed in
                XCTAssertTrue(allowed)
                depth += 1
                maximumDepth = max(maximumDepth, depth)
                count += 1
                if count < 32 { askAgain() }
                depth -= 1
            }
        }
        askAgain()
        XCTAssertEqual(count, 32)
        XCTAssertEqual(maximumDepth, 1)
        XCTAssertTrue(context.events.isEmpty)
        XCTAssertTrue(context.binding.prompts.isEmpty)
    }

    func testWebKitBindingRoutesQuestionsAndAnswersThroughTheNativeOwner() throws {
        let context = try Context()
        var dialogs: [Bool] = []
        context.binding.raise(dialog, for: context.page.id) { accepted, _ in dialogs.append(accepted) }
        XCTAssertEqual(dialogs, [false], "A page without a presenter declines exactly once")
        try context.core.send(
            DecideSitePermission(
                spaceID: context.spaceID, origin: origin, permission: .location, detail: nil,
                decision: .grantPersistently))
        var allowed: [Bool] = []
        context.binding.raise(
            PermissionQuestion(permission: .location, origin: origin, topLevelOrigin: origin), for: context.page.id
        ) { allowed.append($0) }
        XCTAssertEqual(allowed, [true])
        XCTAssertTrue(context.binding.prompts.isEmpty)
    }

    func testUnregisteredBindingCannotRaiseOrWithdrawTheRegisteredBindingsPrompt() throws {
        let context = try Context()
        let other = WebKitEngineBinding(
            profileStores: WebKitBrowserWebsiteDataStoreRemover(), contentBlocking: WebKitContentBlocking())
        let id = context.request(.location, origin: origin) { _ in }
        context.prompts.report(PromptWithdrawn(promptID: id), from: other)
        XCTAssertEqual(context.events.count, 1)
        try context.prompts.send(AnswerPermission(promptID: id, grants: false, remembers: false))
        XCTAssertEqual(context.events.count, 2)
    }
}
