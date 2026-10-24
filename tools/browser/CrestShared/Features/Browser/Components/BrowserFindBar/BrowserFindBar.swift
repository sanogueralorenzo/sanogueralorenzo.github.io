import SwiftUI

// MARK: - Types

enum BrowserFindBarField: Hashable {
    case query
}

/// Find in page, on every shell.
///
/// Everything the bar needs from the page arrives through `BrowserFindPort`,
/// everything about how big it is comes from `BrowserFindBarMetrics`, and the
/// two things a shell genuinely dresses differently — the surface under the bar
/// and what the query field does to typed text — arrive through its own
/// `BrowserPlatform*` pair. So the two shells share this bar rather than a
/// resemblance.
///
/// Focus is not one of those things. Both shells ask for the query field
/// outright, keyed on the page's focus request, because both have the same
/// problem: a bar that is already on screen when find is asked for again has
/// nothing else to notice. macOS declared a default focus for the scope
/// instead, which the window only evaluates as the scope appears — so the
/// second `⌘F` left the field alone, and after the move it stopped landing on
/// the first one too.
struct BrowserFindBar: View {
    let port: BrowserFindPort
    let capabilities: BrowserInteractionCapabilities
    let isPageActive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var focusedField: BrowserFindBarField?

    var body: some View {
        HStack(spacing: metrics.itemSpacing) {
            queryField

            BrowserFindMatchStatus(state: port.matchState(), matches: port.matches(), metrics: metrics)

            control(
                "Previous Match",
                systemImage: "chevron.up",
                isEnabled: !query.isEmpty
            ) {
                port.find(query, .backward)
            }

            control(
                "Next Match",
                systemImage: "chevron.down",
                isEnabled: !query.isEmpty
            ) {
                port.find(query, .forward)
            }

            control("Close Find", systemImage: "xmark", action: port.dismiss)
        }
        .labelStyle(.iconOnly)
        .padding(.leading, metrics.leadingPadding)
        .padding(.trailing, metrics.trailingPadding)
        .modifier(
            BrowserFindBarBand(
                height: metrics.barHeight,
                growsWithContent: metrics.growsWithContent
            )
        )
        .modifier(BrowserPlatformFindBarStyle())
        .shadow(
            color: .black.opacity(
                reduceTransparency ? 0 : BrowserFindBarMetrics.shadowOpacity
            ),
            radius: BrowserFindBarMetrics.shadowRadius,
            y: BrowserFindBarMetrics.shadowOffset
        )
        .task(
            id: FocusTaskID(
                request: port.focusRequest(),
                isPageActive: isPageActive
            )
        ) {
            guard isPageActive, port.focusesQueryField() else { return }
            // The returning NSViewRepresentable finishes its AppKit focus
            // replay during layout. Resume afterward so the page-owned chrome,
            // not the reattached WebKit view, remains authoritative.
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedField = .query
        }
        .onKeyPress(.escape) {
            port.dismiss()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("find-bar")
    }

    private var queryField: some View {
        TextField("Find in Page", text: queryBinding)
            .textFieldStyle(.plain)
            .modifier(BrowserPlatformFindQueryInputModifier())
            .focused($focusedField, equals: .query)
            .frame(width: metrics.queryWidth)
            .onSubmit {
                port.find(port.query(), .forward)
            }
            .accessibilityIdentifier("find-field")
    }

    /// One of the bar's three glyph controls, claiming a hit target only where
    /// the shell's profile asks for one.
    @ViewBuilder
    private func control(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(title, systemImage: systemImage, action: action)
            .disabled(!isEnabled)

        if let controlSize = metrics.controlSize {
            button
                .frame(width: controlSize.width, height: controlSize.height)
                .contentShape(.rect)
        } else {
            button
        }
    }

    private var metrics: BrowserFindBarMetrics {
        BrowserFindBarMetrics.resolve(capabilities)
    }

    private var query: String { port.query() }

    /// Typing searches; writing back the same query does not. macOS hands the
    /// unchanged text to the binding three times on Return, ahead of
    /// `onSubmit`, and each of those would otherwise step to another match.
    private var queryBinding: Binding<String> {
        Binding(
            get: { port.query() },
            set: { query in
                guard query != port.query() else { return }
                port.find(query, .forward)
            }
        )
    }

    private struct FocusTaskID: Hashable {
        let request: Int
        let isPageActive: Bool
    }
}

#if DEBUG
    #Preview("Interactive find field") {
        @Previewable @State var query = "Crest"
        @Previewable @State var match: BrowserFindMatchState = .found
        BrowserFindBar(
            port: BrowserFindPort(
                find: { text, _ in
                    query = text
                    match = text.isEmpty ? .idle : .found
                }, query: { query }, matchState: { match }, focusRequest: { 0 },
                dismiss: {
                    query = ""
                    match = .idle
                }),
            capabilities: BrowserInteractionCapabilities(), isPageActive: true
        ).padding().frame(width: 480)
    }
#endif
