import Foundation

extension CredentialCaptureAction {
    /// Takes the action on `performer`, by its method for this action.
    @MainActor func take<Performer: CredentialCapturePerformer>(
        _ observation: Performer.FormObservation, on performer: Performer
    ) {
        switch self {
        case .ignore: performer.ignore(observation)
        case .rememberUsername: performer.rememberUsername(observation)
        case .dismissFill: performer.dismissFill(observation)
        case .offerFill: performer.offerFill(observation)
        case .captureCandidate: performer.captureCandidate(observation)
        case .offerSave: performer.offerSave(observation)
        case .keepPending: performer.keepPending(observation)
        case .discardPending: performer.discardPending(observation)
        }
    }
}
