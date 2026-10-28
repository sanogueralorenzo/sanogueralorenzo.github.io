import SwiftUI

struct BrowserSoftwareUpdateActions: View {
    // MARK: - Variables

    let model: BrowserSoftwareUpdateModel
    /// Whether Return dismisses a settled update. Only the update window, which
    /// holds nothing else, takes Return for that.
    var confirmsWithReturn = true

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            if let buttons = model.phase.windowButtons(for: model.snapshot) {
                ForEach(buttons.leading, id: \.action, content: button)
                Spacer()
                ForEach(buttons.trailing, id: \.action, content: button)
            }
        }
        .tint(CrestBrandTheme.accent)
    }

    // MARK: - Actions - Buttons

    @ViewBuilder
    private func button(_ button: BrowserSoftwareUpdatePhase.WindowButton) -> some View {
        if let destination = button.destination {
            prominence(Link(destination: destination) { Text(button.title) }, button)
        } else {
            prominence(
                Button {
                    button.action.perform(on: model)
                } label: {
                    Text(button.title)
                }
                .keyboardShortcut(button.confirms && confirmsWithReturn ? .defaultAction : nil),
                button
            )
        }
    }

    @ViewBuilder
    private func prominence(_ content: some View, _ button: BrowserSoftwareUpdatePhase.WindowButton) -> some View {
        if button.isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content
        }
    }
}

#if DEBUG
    #Preview("Update available") {
        let model = BrowserSoftwareUpdateModel()
        BrowserSoftwareUpdateActions(model: model)
            .padding().frame(width: 500)
            .task {
                model.presentUpdate(
                    title: "Crest Update", version: "1.0", releaseNotes: "A new update is ready.",
                    isInformationOnly: false, install: {}, skip: {})
            }
    }
#endif
