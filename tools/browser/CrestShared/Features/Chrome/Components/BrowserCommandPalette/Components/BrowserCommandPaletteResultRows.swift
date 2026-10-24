import SwiftUI

struct BrowserCommandPaletteResultRows: View {
    let model: BrowserCommandPaletteModel
    let group: BrowserCommandPaletteGroup

    var body: some View {
        ForEach(group.items) { item in
            if item.row.kind.isPrimary || group.section == .topHit {
                BrowserCommandPaletteIntentRow(model: model, item: item)
                    .id(item.id)
            } else {
                BrowserCommandPaletteResultRow(model: model, item: item, namesKind: group.section == .results)
                    .id(item.id)
            }
        }
    }
}
