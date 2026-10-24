import SwiftUI

/// What the page can say about the search, spelled the way the shell has room
/// for.
///
/// Both spellings answer the same question with the width each shell can spare:
/// a floating panel can afford "No match" in words, while a bar that already
/// spans a phone's chrome spends that width on the query instead. Neither draws
/// anything before a search has been asked for. An engine that counts its
/// matches has them shown as "3 of 12" in either spelling.
struct BrowserFindMatchStatus: View {
    let state: BrowserFindMatchState
    var matches: BrowserFindMatches?
    let metrics: BrowserFindBarMetrics

    @ViewBuilder
    var body: some View {
        switch metrics.matchStatusStyle {
        case .label:
            spelledOut
        case .symbol:
            drawn
        }
    }

    /// The state in words, red only where the page has nothing to show.
    @ViewBuilder
    private var spelledOut: some View {
        if let counted {
            Text("\(counted.active) of \(counted.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(
                    minWidth: metrics.matchStatusWidth,
                    alignment: .trailing
                )
                .accessibilityLabel(Text("Match \(counted.active) of \(counted.total)"))
                .accessibilityIdentifier("find-result")
        } else if let label = state.label {
            Text(label)
                .font(.caption)
                .foregroundStyle(labelColor)
                .frame(
                    minWidth: metrics.matchStatusWidth,
                    alignment: .trailing
                )
                .accessibilityIdentifier("find-result")
        }
    }

    /// The same states as a symbol, each in the same narrow column, carrying
    /// the words as their accessibility label instead.
    @ViewBuilder
    private var drawn: some View {
        if let counted {
            Text("\(counted.active)/\(counted.total)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(
                    width: metrics.matchStatusWidth,
                    height: metrics.barHeight
                )
                .accessibilityLabel(Text("Match \(counted.active) of \(counted.total)"))
                .accessibilityIdentifier("find-result")
        } else if let label = state.label {
            symbol
                .frame(
                    width: metrics.matchStatusWidth,
                    height: metrics.barHeight
                )
                .accessibilityLabel(Text(label))
                .accessibilityIdentifier("find-result")
        }
    }

    /// The counts, only for a search that found something.
    private var counted: BrowserFindMatches? {
        state == .found ? matches : nil
    }

    @ViewBuilder
    private var symbol: some View {
        if state.showsProgress {
            ProgressView()
                .controlSize(.small)
        } else if let symbol = state.symbol {
            Image(systemName: symbol)
                .foregroundStyle(symbolColor)
        }
    }

    /// Words stay quiet unless the page has nothing to show.
    private var labelColor: Color {
        state.readsAsFailure ? .red : .secondary
    }

    private var symbolColor: Color {
        if state.readsAsFailure { return .red }
        return state.readsAsSuccess ? .green : .secondary
    }
}

#if DEBUG
    #Preview("Search states on pointer and touch") {
        VStack(spacing: 16) {
            HStack {
                BrowserFindMatchStatus(state: .searching, metrics: .pointer)
                BrowserFindMatchStatus(state: .found, metrics: .pointer)
                BrowserFindMatchStatus(
                    state: .found, matches: BrowserFindMatches(active: 3, total: 12), metrics: .pointer)
                BrowserFindMatchStatus(state: .notFound, metrics: .pointer)
            }
            HStack {
                BrowserFindMatchStatus(state: .searching, metrics: .touch)
                BrowserFindMatchStatus(state: .found, metrics: .touch)
                BrowserFindMatchStatus(state: .notFound, metrics: .touch)
            }
        }.padding()
    }
#endif
