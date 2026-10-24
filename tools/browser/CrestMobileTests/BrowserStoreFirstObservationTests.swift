import Observation
import XCTest

@testable import CrestMobile

@MainActor
final class BrowserStoreFirstObservationTests: XCTestCase {
    /// SwiftUI can render while a change is still being announced. Whatever
    /// reads the state there has to see the new value, or the view keeps the
    /// old one and is never told about the change again.
    func testObserverNotifiedOfAChangeReadsTheNewValue() {
        let presentation = BrowserUtilityPresentationState()
        let seen = SeenValue()
        withObservationTracking {
            _ = presentation.isSiteControlPresented
        } onChange: {
            MainActor.assumeIsolated { seen.value = presentation.isSiteControlPresented }
        }

        presentation.setSiteControlPresented(true)

        XCTAssertEqual(seen.value, true)
    }
}

@MainActor
private final class SeenValue {
    var value: Bool?
}
