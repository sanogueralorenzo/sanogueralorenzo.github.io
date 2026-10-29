import Foundation
import XCTest

@testable import Crest

final class NativePagePolicyTests: XCTestCase {
    private typealias Row = [String: Any]
    private func rows(_ section: String, count: Int) throws -> [Row] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/native-page-policy-crest-baseline.json")
        let data = try Data(contentsOf: url)
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? Row)
        let rows = try XCTUnwrap(fixture[section] as? [Row])
        XCTAssertEqual(rows.count, count)
        return rows
    }
    private func origin(_ row: Row) throws -> SiteOrigin {
        SiteOrigin(
            scheme: try XCTUnwrap(row["scheme"] as? String), host: try XCTUnwrap(row["host"] as? String),
            port: try XCTUnwrap(row["port"] as? Int))
    }
    private func popup(_ row: Row) throws -> BrowserBlockedPopupPageState {
        var notice: BrowserBlockedPopupNotice?
        if let name = row["status"] as? String {
            notice = BrowserBlockedPopupNotice(
                origin: try origin(XCTUnwrap(row["origin"] as? Row)),
                status: try XCTUnwrap(BlockedPopupStatus.named(name)))
        }
        return BrowserBlockedPopupPageState(
            notice: notice, documentIdentifier: row["documentIdentifier"] as? String,
            indicationRevision: try XCTUnwrap(row["indicationRevision"] as? Int))
    }
    func testNamedPolicyValuesKeepTheirJSONNames() throws {
        func check<Value: CoreNamedValue>(_ values: [Value]) throws {
            for value in values {
                let encoded = try JSONEncoder().encode(value)
                XCTAssertEqual(try JSONDecoder().decode(String.self, from: encoded), value.name)
                XCTAssertEqual(try JSONDecoder().decode(Value.self, from: encoded).name, value.name)
            }
        }
        try check(BlockedPopupStatus.allCases)
        try check(ExternalSchemeDisposition.allCases)
        try check(HostedNotificationRequestAction.allCases)
    }

    func testHeldAddressesLoadVerbatimWithoutTypedSearchRules() {
        let page = "data:text/html;charset=utf-8," + String(repeating: "%3Cp%3EShowcase%3C%2Fp%3E", count: 400)
        XCTAssertEqual(PageAddress.held(page), page)
        XCTAssertEqual(PageAddress.held("blob:https://example.com/0f1e"), "blob:https://example.com/0f1e")
        for address in [
            "javascript:alert(1)", "mailto:crest@example.com", "chrome://extensions/", "crest://version/",
            "chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html",
        ] {
            XCTAssertNil(PageAddress.held(address))
        }
    }

    func testPagePresentationMatchesCrestForEverySurfaceAndFailureCombination() throws {
        for row in try rows("presentation", count: 64) {
            let answer = PagePresentation.of(
                TabSurface.named(row["surface"] as? String), hasPage: row["hasPage"] as! Bool,
                hasNavigationFailure: row["hasNavigationFailure"] as! Bool,
                hasProcessFailure: row["hasProcessFailure"] as! Bool, restoresUnloaded: row["restoresUnloaded"] as! Bool
            )
            XCTAssertEqual(answer.rawValue, row["answer"] as? String, "\(row)")
        }
    }
    func testAuthenticationHandlingAndLabelsMatchCrest() throws {
        for row in try rows("authentication", count: 42) {
            let answer = AuthenticationHandling.handling(
                method: try XCTUnwrap(AuthenticationMethod(rawValue: row["method"] as! String)),
                isProxy: row["proxy"] as! Bool, previousFailureCount: row["failures"] as! Int)
            let expected: AuthenticationHandling
            switch row["answer"] as! String {
            case "PromptForCredentials": expected = .promptForCredentials
            case "PerformDefaultHandling": expected = .performDefaultHandling
            case "Cancel": expected = .cancel
            default: return XCTFail("Unknown handling")
            }
            XCTAssertEqual(answer, expected)
        }
        for row in try rows("labels", count: 105) {
            XCTAssertEqual(
                AuthenticationSource.label(
                    host: row["host"] as! String, port: row["port"] as! Int,
                    scheme: row["scheme"] as? String, emptyHostLabel: "Browser"),
                row["answer"] as? String ?? "Browser")
        }
    }
    func testSchemeAndLocalDocumentDecisionsMatchCrest() throws {
        for row in try rows("schemes", count: 44) {
            XCTAssertEqual(
                SchemeHandling.disposition(
                    scheme: row["scheme"] as? String, isAppInitiated: row["appInitiated"] as! Bool
                ).name,
                row["answer"] as? String)
        }
        for row in try rows("locals", count: 56) {
            XCTAssertEqual(
                ExternalLocalDocument.accepts(
                    isFile: row["isFile"] as! Bool, hasUser: row["hasUser"] as! Bool,
                    hasPath: row["hasPath"] as! Bool, host: row["host"] as? String),
                row["answer"] as? Bool)
        }
    }
    func testOriginNormalizationLengthAndSecureContextMatchCrest() throws {
        for row in try rows("origins", count: 22) {
            let value = try origin(row)
            XCTAssertEqual(value.isValid, row["isValid"] as? Bool)
            XCTAssertEqual(value.displayName, row["displayName"] as? String)
            XCTAssertEqual(value.isSecureContext, row["secure"] as? Bool)
            let roundTrip = try JSONDecoder().decode(SiteOrigin.self, from: JSONEncoder().encode(value))
            XCTAssertEqual(value, roundTrip)
            XCTAssertEqual(value.hashValue, roundTrip.hashValue)
        }
        XCTAssertEqual(
            SiteOrigin(scheme: "HTTPS", host: "EXAMPLE.COM", port: 0),
            SiteOrigin(scheme: "https", host: "example.com", port: 443))
    }
    func testPopupTransitionsMatchCrestIncludingMalformedDocumentsAndRevisionOverflow() throws {
        for (index, row) in try rows("popups", count: 175).enumerated() {
            var state = try popup(XCTUnwrap(row["state"] as? Row))
            let before = state
            let changed: Bool
            switch row["event"] as! String {
            case "blocked":
                if let document = row["document"] as? String, let site = row["origin"] as? Row {
                    changed = state.recordBlockedAttempt(documentIdentifier: document, origin: try origin(site))
                } else {
                    changed = false
                }
            case "permission_allowed": changed = state.recordPermissionAllowed()
            case "permission_blocked_again": changed = state.recordPermissionBlockedAgain()
            case "navigation": changed = state.clearForNavigation()
            case "popup_allowed": changed = state.clearAfterAllowedPopup()
            default: return XCTFail("Unknown popup event")
            }
            let expected = try (row["next"] as? Row).map(popup)
            XCTAssertEqual(changed, expected != nil, "Row \(index)")
            XCTAssertEqual(state, expected ?? before, "Row \(index)")
        }
    }
    func testNotificationConsentAndPermissionMetadataMatchCrest() throws {
        for row in try rows("notifications", count: 10) {
            XCTAssertEqual(
                HostedNotificationRequestAction.action(
                    decision: try XCTUnwrap(SitePermissionDecision.named(row["decision"] as? String)),
                    hasUserActivation: row["gesture"] as! Bool
                ).name, row["answer"] as? String)
        }
        let permissions = try rows("permissions", count: 9)
        XCTAssertEqual(SitePermission.all.map(\.name), permissions.map { $0["name"] as! String })
        for row in permissions {
            let permission = try XCTUnwrap(SitePermission.named(row["name"] as? String))
            XCTAssertEqual(String(localized: permission.title), row["title"] as? String)
            XCTAssertEqual(permission.symbol, row["symbol"] as? String)
            XCTAssertEqual(String(localized: permission.requestTitle), row["requestTitle"] as? String)
            XCTAssertEqual(String(localized: permission.askTitle), row["askTitle"] as? String)
            XCTAssertEqual(String(localized: permission.askChoiceTitle), row["askChoiceTitle"] as? String)
            XCTAssertEqual(permission.isMedia, row["isMedia"] as? Bool)
            XCTAssertEqual(permission.isEngineEnforced, row["isEngineEnforced"] as? Bool)
            XCTAssertEqual(permission.isAskedBySystem, row["isAskedBySystem"] as? Bool)
            XCTAssertEqual(permission.components.map(\.name), row["components"] as? [String])
            XCTAssertEqual(permission.devices.map(\.name), row["devices"] as? [String])
            XCTAssertEqual(permission.combinations.map(\.name), row["combinations"] as? [String])
            XCTAssertEqual(
                try JSONDecoder().decode(SitePermission.self, from: JSONEncoder().encode(permission)), permission)
        }
        for row in try rows("decisions", count: 5) {
            let decision = try XCTUnwrap(SitePermissionDecision.named(row["name"] as? String))
            XCTAssertEqual(String(localized: decision.title), row["title"] as? String)
            XCTAssertEqual(decision.grants, row["grants"] as? Bool)
            XCTAssertEqual(decision.denies, row["denies"] as? Bool)
            XCTAssertEqual(decision.asks, row["asks"] as? Bool)
            XCTAssertEqual(decision.isPersistent, row["isPersistent"] as? Bool)
            XCTAssertEqual(decision.precedence, row["precedence"] as? Int)
            XCTAssertEqual(
                try JSONDecoder().decode(SitePermissionDecision.self, from: JSONEncoder().encode(decision)), decision)
        }
    }
}
