import SwiftUI

/// Makes a reviewed Space yours before it is imported, in the look setup
/// chose. Setup holds each choice; Done returns to the review.
struct BrowserImportSpaceCustomizationView: View {
    let flow: BrowserImportFlow
    let spaceID: UUID
    let previewSpace: SpaceModel?
    let done: () -> Void

    @ViewBuilder
    var body: some View {
        if let review {
            VStack(spacing: 24) {
                Text("Edit Name").font(.title)
                Spacer()
                BrowserSpaceIdentityIcon(identity: identity(of: review), size: 64)
                BrowserSpaceIdentityEditor(
                    name: Binding(
                        get: { self.review?.customization.name ?? "" },
                        set: { flow.customize(spaceID, as: SpaceCustomization(name: $0)) }), color: nil)
                Spacer()
                BrowserImportFooter(back: nil) {
                    Button("Done", action: done).buttonStyle(.crestPrimary)
                }
            }
            .padding(.top, 32)
        }
    }

    private var review: BrowserImportSpaceReview? {
        flow.reviewSpaces.first { $0.id == spaceID }
    }

    /// The Space as its icon draws it: the one the import would make, wearing
    /// the review's choices.
    private func identity(of review: BrowserImportSpaceReview) -> BrowserSpaceIdentity {
        return (previewSpace ?? review.sourceSpace).identity.wearing(name: review.record.shownName)
    }

}
