import Foundation

extension WindowRecordsAdopted {
    /// The sidebar values the adopted records carried are the platform's own;
    /// the read model keeps nothing of the adoption.
    @MainActor func apply(to state: CoreState) {}
}
