import SwiftUI

struct BrowserUtilityFilterMenu: View {
    let surface: BrowserUtilitySurface
    @Binding var filter: BrowserUtilityListFilter
    var clearHistory: (() -> Void)?

    var body: some View {
        Menu {
            Group {
                Picker("Filter", selection: $filter) {
                    ForEach(surface.filters) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }

                if let clearHistory, surface.clearsHistory {
                    Divider()
                    Button(
                        "Clear History",
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        clearHistory()
                    }
                }
            }
            .crestMenuActionLabelStyle()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .frame(
                    width: BrowserUtilitySwitcherLayout.buttonSize,
                    height: BrowserChromeLayout.addressHeight
                )
                .contentShape(.rect)
        }
        .crestMenuActionLabelStyle()
        .menuIndicator(.hidden)
        .modifier(BrowserPlatformUtilityFilterMenuStyle())
        .help(Text(surface.filterLabel))
        .accessibilityLabel(Text(surface.filterLabel))
        .accessibilityValue(Text(filter.normalized(for: surface).title))
        .accessibilityIdentifier("utility-filter-button")
    }
}

#if DEBUG
    #Preview("History filters") {
        @Previewable @State var filter: BrowserUtilityListFilter = .all
        BrowserUtilityFilterMenu(surface: .history, filter: $filter, clearHistory: {}).padding()
    }
#endif
