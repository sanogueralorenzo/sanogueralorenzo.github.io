import SwiftUI

struct BrowserUtilityListSectionList: View {
    let sections: [BrowserUtilityListSection]
    let assignment: BrowserSpaceRuntimeAssignment
    let actions: BrowserUtilityListActions
    let dismissOnBlankSpace: (() -> Void)?

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        BrowserUtilityListRow(
                            item: item,
                            assignment: assignment,
                            actions: actions
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: CrestSpacing.extraExtraSmall,
                                leading: CrestSpacing.small,
                                bottom: CrestSpacing.extraExtraSmall,
                                trailing: CrestSpacing.small
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(section.timeframe.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {
                    dismissOnBlankSpace?()
                }
        }
        // Preserve native row-height estimates on macOS for long history lists.
        #if !os(macOS)
            .environment(\.defaultMinListRowHeight, 1)
        #endif
    }

}
