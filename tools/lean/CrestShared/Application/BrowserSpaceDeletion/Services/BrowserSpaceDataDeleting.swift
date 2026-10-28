/// Erases what the platform and every engine keep for a Space's profile
/// before the core lets the Space go.
@MainActor
protocol BrowserSpaceDataDeleting: AnyObject {
    /// Erases the data of the Space `space` names, in its profile.
    func deleteData(for space: BrowserSpaceRuntimeAssignment) async throws
}
