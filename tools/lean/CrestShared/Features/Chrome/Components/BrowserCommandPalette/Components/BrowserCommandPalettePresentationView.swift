import SwiftUI

struct BrowserCommandPalettePresentationView: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let morphNamespace: Namespace.ID?
    let overlayContentLeadingInset: CGFloat
    var overlayContentInsets: EdgeInsets? = nil
    let queryIsFocused: FocusState<Bool>.Binding

    @ViewBuilder
    var body: some View {
        if presentation == .overlay {
            GeometryReader { proxy in
                let availableHeight =
                    proxy.size.height - contentInsets.top - contentInsets.bottom
                let maximumResultAreaHeight =
                    BrowserCommandPaletteLayout
                    .overlayResultAreaHeight(availableHeight: availableHeight)

                ZStack {
                    BrowserCommandPaletteScrim(dismiss: model.dismiss)
                    BrowserCommandPaletteCard(
                        model: model,
                        presentation: presentation,
                        maximumResultAreaHeight: maximumResultAreaHeight,
                        morphNamespace: morphNamespace,
                        restingWidth: BrowserCommandPaletteLayout.overlayCardWidth(
                            availableWidth: proxy.size.width - contentInsets.leading - contentInsets.trailing
                        ),
                        queryIsFocused: queryIsFocused
                    )
                    .padding(.horizontal, BrowserCommandPaletteMetrics.overlayCardPadding)
                    .padding(.top, BrowserCommandPaletteLayout.overlayTopInset(availableHeight: availableHeight))
                    .padding(.bottom, BrowserCommandPaletteMetrics.overlayCardPadding)
                    // The top edge stays put while results change; the card grows down.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(contentInsets)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            BrowserCommandPaletteCard(
                model: model,
                presentation: presentation,
                maximumResultAreaHeight: BrowserCommandPaletteLayout.maximumResultAreaHeight,
                morphNamespace: nil,
                restingWidth: nil,
                queryIsFocused: queryIsFocused
            )
        }
    }

    /// The part of the overlay the page's chrome keeps, which the card and
    /// its results stay clear of.
    private var contentInsets: EdgeInsets {
        overlayContentInsets
            ?? EdgeInsets(top: 0, leading: overlayContentLeadingInset, bottom: 0, trailing: 0)
    }
}
