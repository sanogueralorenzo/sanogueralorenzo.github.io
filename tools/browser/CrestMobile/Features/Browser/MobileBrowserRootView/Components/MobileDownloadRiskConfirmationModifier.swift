import SwiftUI

/// Presents the shared risky-download confirmation for the profiles this
/// window browses.
struct MobileDownloadRiskConfirmationModifier: ViewModifier {
    @Bindable var confirmation: MobileDownloadRiskConfirmationCoordinator
    let profileIDs: Set<UUID>
    /// Whether this view asks, rather than one drawn over it: an alert asked
    /// of a view another view covers never appears, and the download waits.
    var asks = true

    func body(content: Content) -> some View {
        content.alert(
            confirmation.request?.title ?? "Download file?",
            isPresented: Binding(
                get: { asks && (confirmation.request.map { profileIDs.contains($0.profileID) } ?? false) },
                set: { if asks { confirmation.isPresented = $0 } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                confirmation.cancel()
            }
            Button("Download", role: .destructive) {
                confirmation.approve()
            }
        } message: {
            if let request = confirmation.request {
                Text(request.message)
            }
        }
    }
}
