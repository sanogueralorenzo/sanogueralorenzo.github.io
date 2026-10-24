import Foundation
import SwiftUI

struct BrowserDownloadFinishedAction: View {
    let itemID: UUID
    let action: DownloadRowAction
    let destinations: [BrowserUtilityDownloadDestination]
    let perform: (BrowserUtilityDownloadAction) -> Void

    var body: some View {
        if destinations.count == 1, let destination = destinations.first {
            Button(destination.title, systemImage: destination.symbol) {
                perform(.open(itemID, destination))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(
                width: BrowserUtilitySwitcherLayout.buttonSize,
                height: BrowserUtilitySwitcherLayout.buttonSize
            )
        } else if !destinations.isEmpty {
            ZStack {
                Image(systemName: action.symbol)
                    .accessibilityHidden(true)

                Menu {
                    ForEach(destinations) { destination in
                        Button(destination.title, systemImage: destination.symbol) {
                            perform(.open(itemID, destination))
                        }
                    }
                    .crestMenuActionLabelStyle()
                } label: {
                    Color.clear
                        .frame(
                            width: BrowserUtilitySwitcherLayout.buttonSize,
                            height: BrowserUtilitySwitcherLayout.buttonSize
                        )
                        .contentShape(.rect)
                }
                .crestMenuActionLabelStyle()
                .menuIndicator(.hidden)
                .modifier(BrowserPlatformUtilityFilterMenuStyle())
                .frame(
                    width: BrowserUtilitySwitcherLayout.buttonSize,
                    height: BrowserUtilitySwitcherLayout.buttonSize
                )
                .clipped()
                .accessibilityLabel(Text(action.title))
            }
            .frame(
                width: BrowserUtilitySwitcherLayout.buttonSize,
                height: BrowserUtilitySwitcherLayout.buttonSize
            )
            .help(Text(action.title))
        }
    }
}
