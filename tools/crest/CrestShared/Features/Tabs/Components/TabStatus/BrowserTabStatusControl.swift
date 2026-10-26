import SwiftUI

/// One status mark a person can use: a button that runs the mark's action, or
/// a menu of its actions when it offers several. The label is the mark as its
/// host draws it; when the mark changes to another of the same status, its
/// symbol is replaced in place.
struct BrowserTabStatusControl<Label: View>: View {
    // MARK: - Variables

    let mark: BrowserTabStatusMark
    let tab: BrowserTabStatusSource
    @ViewBuilder let label: () -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        control
            .help(Text(mark.title))
            .animation(
                CrestMotion.contentState.unlessReducingMotion(reduceMotion),
                value: mark
            )
    }

    // MARK: - Actions - Layout

    @ViewBuilder
    private var control: some View {
        let actions = mark.actions.filter { $0.isAvailable(tab) }
        if actions.count > 1 {
            Menu {
                ForEach(actions.indices, id: \.self) { index in
                    item(actions[index])
                }
                .crestMenuActionLabelStyle()
            } label: {
                label()
            }
            .crestMenuActionLabelStyle()
            .menuIndicator(.hidden)
            .menuStyle(.button)
            .accessibilityLabel(Text(mark.title))
        } else if let action = actions.first {
            Button(role: action.role) {
                action.run(on: tab)
            } label: {
                label()
            }
            .accessibilityLabel(Text(action.title))
            .accessibilityValue(Text(mark.title))
        } else {
            label()
                .accessibilityElement()
                .accessibilityLabel(Text(mark.title))
        }
    }

    private func item(_ action: BrowserTabStatusAction) -> some View {
        Button(role: action.role) {
            action.run(on: tab)
        } label: {
            SwiftUI.Label {
                Text(action.title)
            } icon: {
                Image(systemName: action.symbol)
            }
        }
    }
}
