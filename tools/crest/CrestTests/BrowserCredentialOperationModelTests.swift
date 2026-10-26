import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialOperationModelTests: XCTestCase {
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

}

private enum TestFailure: Error {
    case expected
}
