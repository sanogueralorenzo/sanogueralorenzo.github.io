import Foundation

/// What the software update card's actions ask of the updater behind it.
@MainActor
protocol BrowserSoftwareUpdateActionPerformer: AnyObject {
    func chooseAutomaticChecks(_ isEnabled: Bool)
    func installUpdate()
    func skipUpdate()
    func cancelCurrentOperation()
    func installAndRelaunchNow()
    func retryApplicationTermination()
    func acknowledge()
    func hide()
}
