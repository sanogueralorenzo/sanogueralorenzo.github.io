import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserSettingsPaneTests: XCTestCase {
    func testKeyboardDismissalIgnoresReplacedRequestsAndDepartedOwners() async {
        let waiting = (0..<3).map { expectation(description: "Keyboard dismissal \($0) is waiting") }
        let currentDismissal = expectation(description: "Current keyboard dismissal finishes")
        var continuations: [CheckedContinuation<Void, Never>] = []
        var dismissals: [String] = []
        let dismissal = BrowserSearchEngineKeyboardDismissal(delay: .zero) { _ in
            let index = continuations.count
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
                waiting[index].fulfill()
            }
        }

        dismissal.schedule { dismissals.append("replaced") }
        await fulfillment(of: [waiting[0]], timeout: 1)
        dismissal.schedule { dismissals.append("departed") }
        await fulfillment(of: [waiting[1]], timeout: 1)
        dismissal.cancel()
        dismissal.schedule {
            dismissals.append("current")
            currentDismissal.fulfill()
        }
        await fulfillment(of: [waiting[2]], timeout: 1)

        for continuation in continuations { continuation.resume() }
        await fulfillment(of: [currentDismissal], timeout: 1)

        XCTAssertEqual(dismissals, ["current"])
    }
}
