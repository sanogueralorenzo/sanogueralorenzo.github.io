import Foundation

extension CloudSyncStepKind {
    /// Takes `step`, a step of this kind, on `performer`, and answers the
    /// steps its report leads to.
    @MainActor func take(_ step: CloudSyncStep, on performer: some CloudSyncStepPerformer) async -> [CloudSyncStep] {
        switch kind {
        case .checkEntitlement: await performer.checkEntitlement(step)
        case .checkAccount: await performer.checkAccount(step)
        case .replaceSeed: await performer.replaceSeed(step)
        case .compareContent: await performer.compareContent(step)
        case .takeCloudContent: await performer.takeCloudContent(step)
        case .applyChosenCopy: await performer.applyChosenCopy(step)
        case .startTransport: await performer.startTransport(step)
        case .discardStartedTransport: await performer.discardStartedTransport(step)
        case .stopTransport: await performer.stopTransport(step)
        case .syncTransport: await performer.syncTransport(step)
        case .pullTransport: await performer.pullTransport(step)
        case .notifyTransport: await performer.notifyTransport(step)
        case .scheduleRetry: await performer.scheduleRetry(step)
        case .cancelRetry: await performer.cancelRetry(step)
        case .restartAfterAccountChange: await performer.restartAfterAccountChange(step)
        }
    }
}
