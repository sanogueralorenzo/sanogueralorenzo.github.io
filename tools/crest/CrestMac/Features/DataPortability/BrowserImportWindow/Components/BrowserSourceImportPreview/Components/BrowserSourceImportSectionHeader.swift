import SwiftUI

struct BrowserSourceImportSectionHeader: View {
    let title: LocalizedStringResource
    let tabs: [TabStateModel]
    let includedTabIDs: Set<UUID>
    let setIncluded: (Set<UUID>, Bool) -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(includesAll ? "Leave all" : "Include all") {
                setIncluded(tabIDs, !includesAll)
            }
            .buttonStyle(.borderless)
            .font(.caption2)
        }
        .frame(height: 24)
    }

    private var tabIDs: Set<UUID> { Set(tabs.map(\.id)) }
    private var includesAll: Bool { tabIDs.isSubset(of: includedTabIDs) }
}
