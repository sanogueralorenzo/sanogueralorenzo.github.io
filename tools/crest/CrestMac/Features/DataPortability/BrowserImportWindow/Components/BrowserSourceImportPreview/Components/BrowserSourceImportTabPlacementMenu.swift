import SwiftUI

struct BrowserSourceImportTabPlacementMenu: View {
    let tab: TabStateModel
    let setPlacement: (UUID, TabPlacement) -> Void

    var body: some View {
        Menu {
            Group {
                ForEach(TabPlacement.all, id: \.self) { placement in
                    Button(placement.title, systemImage: placement.symbol) {
                        setPlacement(tab.id, placement)
                    }
                }
            }
            .crestMenuActionLabelStyle()
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 22, height: 22)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .crestMenuActionLabelStyle()
        .fixedSize()
        .accessibilityLabel(Text("Tab placement for \(tab.title)"))
        .accessibilityValue(Text(tab.placement.title))
    }
}
