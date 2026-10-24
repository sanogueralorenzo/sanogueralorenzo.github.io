import CoreLocation
import XCTest

@testable import Crest

@MainActor
final class BrowserGeolocationSystemServiceTests: XCTestCase {
    func testUnansweredAuthorizationFinishesWithoutRecordingDenialAndCanBeRetried() async {
        let manager = TestLocationManager()
        let service = BrowserGeolocationSystemService(manager: manager, authorizationTimeout: .milliseconds(30))
        async let first = service.requestAuthorization()
        async let second = service.requestAuthorization()
        let results = await [first, second]
        XCTAssertEqual(results, [.notDetermined, .notDetermined])
        XCTAssertEqual(manager.requestCount, 1)

        manager.response = .authorizedAlways
        let retry = await service.requestAuthorization()
        XCTAssertEqual(retry, .authorized)
        XCTAssertEqual(manager.requestCount, 2)
        let cached = await service.requestAuthorization()
        XCTAssertEqual(cached, .authorized)
        XCTAssertEqual(manager.requestCount, 2, "Approved access must not trigger another prompt.")
    }

    func testSystemDenialCompletesPendingRequests() async {
        let manager = TestLocationManager()
        manager.response = .denied
        let service = BrowserGeolocationSystemService(manager: manager)
        let result = await service.requestAuthorization()
        XCTAssertEqual(result, .denied)
        let retry = await service.requestAuthorization()
        XCTAssertEqual(retry, .denied)
        XCTAssertEqual(manager.requestCount, 1)
    }
}

private final class TestLocationManager: CLLocationManager {
    var response: CLAuthorizationStatus?
    var requestCount = 0
    private var status: CLAuthorizationStatus = .notDetermined

    override var authorizationStatus: CLAuthorizationStatus { status }

    override func requestWhenInUseAuthorization() {
        requestCount += 1
        if let response {
            status = response
            delegate?.locationManagerDidChangeAuthorization?(self)
        }
    }
}
