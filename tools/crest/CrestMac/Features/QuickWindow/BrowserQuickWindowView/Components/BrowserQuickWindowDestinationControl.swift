import SwiftUI

struct BrowserQuickWindowDestinationControl: View {
    let model: BrowserQuickWindowModel
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    @State private var isPickerPresented = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: promoteCurrentSpace) {
                Text(destinationTitle)
                    .lineLimit(1)
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
                    .frame(height: BrowserQuickWindowLayout.controlHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityIdentifier("quick-window-open-destination")
            BrowserQuickWindowDestinationPickerButton(
                spaces: model.availableSpaceModels.map(\.identity),
                selectedSpaceID: model.selectedAssignment.spaceID,
                isPresented: $isPickerPresented,
                promote: promote
            )
        }
        .font(.callout.weight(.semibold))
        .background {
            CrestSurfaceLayer(
                shape: .rect(cornerRadius: BrowserChromeLayout.addressCornerRadius, style: .continuous)
            )
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: BrowserChromeLayout.addressCornerRadius,
                style: .continuous
            )
            .strokeBorder(CrestColor.subtleBorder, lineWidth: 0.5)
        }
        .fixedSize()
        .help("Open in \(model.spaceModel?.settings.name ?? "Space") (⌘O)")
    }

    /// "Open in" the Space the page would land in.
    private var destinationTitle: String {
        let spaceName = model.spaceModel?.settings.name ?? "Space"
        return String(localized: "Open in \(spaceName)")
    }

    private func promoteCurrentSpace() {
        guard let space = model.spaceModel else { return }
        promote(BrowserSpaceRuntimeAssignment(space: space))
    }
}
