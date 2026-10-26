import Foundation

/// Does to a page's credential state what the core decided one form
/// observation does: one method per capture action, each taking the
/// observation it acts on. An action the core adds fails to compile until
/// every performer takes it.
@MainActor
protocol CredentialCapturePerformer {
    /// The observation, with everything the page knows about it.
    associatedtype FormObservation

    func ignore(_ observation: FormObservation)
    func rememberUsername(_ observation: FormObservation)
    func dismissFill(_ observation: FormObservation)
    func offerFill(_ observation: FormObservation)
    func captureCandidate(_ observation: FormObservation)
    func offerSave(_ observation: FormObservation)
    func keepPending(_ observation: FormObservation)
    func discardPending(_ observation: FormObservation)
}
