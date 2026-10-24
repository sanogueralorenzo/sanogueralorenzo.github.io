import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserSettingsPaneTests: XCTestCase {
    func testMacWebTextAssistanceDisablesAutomaticCorrectionsWithoutDisablingTextReplacement() throws {
        let suiteName = "crest.tests.webkit-text-input.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expectedKeys = Set([
            "WebAutomaticSpellingCorrectionEnabled",
            "WebGrammarCheckingEnabled",
            "WebSmartInsertDeleteEnabled",
            "WebSmartListsEnabled",
            "WebAutomaticQuoteSubstitutionEnabled",
            "WebAutomaticDashSubstitutionEnabled",
            "WebAutomaticLinkDetectionEnabled",
        ])
        for key in BrowserMacWebTextAssistancePreference.disabledSmartTextKeys {
            defaults.set(true, forKey: key)
        }

        BrowserMacWebTextAssistancePreference.configure(
            defaults: defaults
        )

        XCTAssertEqual(
            Set(BrowserMacWebTextAssistancePreference.disabledSmartTextKeys),
            expectedKeys
        )
        XCTAssertEqual(
            BrowserMacWebTextAssistancePreference.disabledSmartTextKeys.count,
            expectedKeys.count
        )
        for key in BrowserMacWebTextAssistancePreference.disabledSmartTextKeys {
            XCTAssertFalse(defaults.bool(forKey: key), key)
        }
    }

    func testTextReplacementRemovesTheLegacyForcedOverrideThenPreservesUserChoices() throws {
        let suiteName = "crest.tests.text-replacement.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "WebAutomaticTextReplacementEnabled"
        defaults.set(false, forKey: key)
        BrowserMacWebTextAssistancePreference.configure(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: key), "WebKit should inherit the macOS text replacement preference")

        for choice in [true, false, true] {
            defaults.set(choice, forKey: key)
            BrowserMacWebTextAssistancePreference.configure(defaults: defaults)
            XCTAssertEqual(defaults.bool(forKey: key), choice)
        }
    }

    // MARK: - Extension status

    /// Both shells used to derive an extension's colour by switching on its English
    /// status *string*. The condition decides once, and the label and colour both
    /// read from the decision.

    // MARK: - Passwords

    /// The pane's search runs over four fields, and both shells had written their own
    /// copy of the predicate.
    func testCredentialSearchMatchesAccountSiteLabelAndScope() {
        let spaceID = UUID()
        let origin = CredentialOrigin(url: URL(string: "https://mail.example")!)!
        let other = CredentialOrigin(url: URL(string: "https://intranet.example")!)!
        let webForm = CredentialDescriptor(
            spaceID: spaceID,
            origin: origin,
            username: "person@example.com",
            displayName: "Work mail"
        )
        let httpBasic = CredentialDescriptor(
            spaceID: spaceID,
            origin: other,
            scope: .httpBasic(realm: "Members"),
            username: "operator"
        )
        let all = [webForm, httpBasic]

        XCTAssertEqual(
            all.matching("  "),
            [httpBasic, webForm],
            "A blank query keeps every password and orders the manager by site."
        )
        XCTAssertEqual(
            all.matching("PERSON"),
            [webForm]
        )
        XCTAssertEqual(
            all.matching("work mail"),
            [webForm]
        )
        XCTAssertEqual(
            all.matching("intranet"),
            [httpBasic]
        )
        XCTAssertEqual(
            all.matching("Realm"),
            [httpBasic],
            "The authentication scope is part of how a reader finds a credential."
        )
    }
}
