import SwiftUI

struct BrowserSpaceBrowsingMenuLabel<Value: View>: View {
    let title: LocalizedStringKey
    let layout: BrowserSpaceBrowsingPickerValueLayout
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: layout.minimumLeadingGap)
            HStack(spacing: layout.disclosureSpacing) {
                value()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, layout.verticalPadding)
        .contentShape(.rect)
    }
}
