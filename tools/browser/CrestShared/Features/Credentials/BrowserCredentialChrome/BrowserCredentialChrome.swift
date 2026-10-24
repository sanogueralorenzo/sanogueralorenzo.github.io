import SwiftUI

/// The credential prompt a page is presenting, on every shell.
///
/// Which prompt that is comes from `BrowserCredentialChromePresentation`, what
/// each prompt can do to the page comes from the two ports, and how each one is
/// drawn comes from what the shell says it can do. Nothing about the chrome is
/// left for a shell to decide twice — including where it goes, which is why the
/// profile is resolved here rather than three times over inside the prompts.
struct BrowserCredentialChrome: View {
    let presentation: BrowserCredentialChromePresentation
    let fillPort: BrowserCredentialFillPort
    let savePort: BrowserCredentialSavePort
    let browser: BrowserStore
    let capabilities: BrowserInteractionCapabilities

    var body: some View {
        BrowserCredentialChromePlacement(
            field: anchoredField,
            metrics: BrowserCredentialPromptMetrics.resolve(capabilities)
        ) { metrics in
            prompt(metrics)
        }
    }

    /// Where the field that raised this prompt sits over the page, in this
    /// shell's points, or `nil` where the prompt is not anchored to one.
    ///
    /// The page reports CSS pixels from its own viewport, and the page's zoom
    /// is the whole of the difference between those and what is on screen —
    /// the chrome is drawn in the web view's own box, so nothing else has to
    /// be undone.
    private var anchoredField: CGRect? {
        guard let rect = presentation.fillRequest?.fieldRect else { return nil }
        let scale = fillPort.contentScale
        guard scale.isFinite, scale > 0 else { return nil }
        return CGRect(
            x: rect.x * scale,
            y: rect.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    @ViewBuilder
    private func prompt(
        _ metrics: BrowserCredentialPromptMetrics
    ) -> some View {
        switch presentation {
        case .none:
            EmptyView()
        case .save(let candidate):
            BrowserCredentialSavePrompt(
                candidate: candidate,
                port: savePort,
                browser: browser,
                metrics: metrics
            )
        case .strongPassword(let request):
            BrowserStrongPasswordPrompt(
                request: request,
                port: fillPort,
                browser: browser,
                metrics: metrics
            )
        case .suggestions(let request):
            BrowserCredentialSuggestionPrompt(
                request: request,
                port: fillPort,
                browser: browser,
                metrics: metrics
            )
        }
    }
}
