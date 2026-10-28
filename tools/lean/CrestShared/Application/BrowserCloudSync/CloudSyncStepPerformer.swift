import Foundation

/// Takes each step of iCloud sync the core decides: one method per kind, each
/// taking the step and answering the steps its report leads to. A kind the
/// core adds fails to compile until the performer takes it.
@MainActor
protocol CloudSyncStepPerformer {
    func checkEntitlement(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func checkAccount(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func replaceSeed(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func compareContent(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func takeCloudContent(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func applyChosenCopy(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func startTransport(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func discardStartedTransport(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func stopTransport(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func syncTransport(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func pullTransport(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func notifyTransport(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func scheduleRetry(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func cancelRetry(_ step: CloudSyncStep) async -> [CloudSyncStep]
    func restartAfterAccountChange(_ step: CloudSyncStep) async -> [CloudSyncStep]
}
