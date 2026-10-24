import SwiftUI

/// Makes a reviewed Space yours before it is imported, in the look setup
/// chose. Setup holds each choice; Done returns to the review.
struct BrowserImportSpaceCustomizationView: View {
    let flow: BrowserOnboardingFlow
    let spaceID: UUID
    let previewSpace: SpaceModel?
    let done: () -> Void

    @ViewBuilder
    var body: some View {
        if let review {
            BrowserOnboardingMakePage(
                look: flow.look,
                branding: brandingBinding,
                symbol: binding(get: \.symbol) { current, symbol in
                    SpaceCustomization(
                        name: current.name, symbol: symbol, accent: current.accent, branding: current.branding)
                },
                name: binding(get: \.name) { current, name in
                    SpaceCustomization(
                        name: name, symbol: current.symbol, accent: current.accent, branding: current.branding)
                },
                identity: identity(of: review),
                back: BrowserOnboardingBackAction(closes: false, action: done),
                advanceTitle: Text("Done"),
                advance: done
            )
        }
    }

    private var review: BrowserImportSpaceReview? {
        flow.reviewSpaces.first { $0.id == spaceID }
    }

    /// The Space as its icon draws it: the one the import would make, wearing
    /// the review's choices.
    private func identity(of review: BrowserImportSpaceReview) -> BrowserSpaceIdentity {
        let customization = review.customization
        return (previewSpace ?? review.sourceSpace).identity.wearing(
            customization.branding, symbol: customization.symbol, name: review.record.shownName)
    }

    /// A binding to one part of the Space's customization, which `set`
    /// replaces in the rest.
    private func binding(
        get: KeyPath<SpaceCustomization, String>,
        set: @escaping (SpaceCustomization, String) -> SpaceCustomization
    ) -> Binding<String> {
        Binding(
            get: { review?.customization[keyPath: get] ?? "" },
            set: { value in
                guard let current = review?.customization else { return }
                flow.customize(spaceID, as: set(current, value))
            }
        )
    }

    private var brandingBinding: Binding<SpaceBranding> {
        Binding(
            get: {
                review.map(\.customization.branding)
                    ?? previewSpace.map(\.settings.look)
                    ?? SpaceAccent.indigo.house
            },
            set: { branding in
                guard let current = review?.customization else { return }
                flow.customize(
                    spaceID,
                    as: SpaceCustomization(
                        name: current.name, symbol: current.symbol, accent: current.accent, branding: branding))
            }
        )
    }
}
