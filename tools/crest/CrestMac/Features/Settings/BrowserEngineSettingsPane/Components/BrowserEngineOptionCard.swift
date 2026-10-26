import SwiftUI

/// One engine as a selectable row: its mark, name and strengths, with a check
/// when it opens new pages.
struct BrowserEngineOptionCard: View {
    // MARK: - Variables

    let option: BrowserEngineOption
    let isSelected: Bool
    let isRecommended: Bool
    let isAvailable: Bool
    let choose: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 12) {
                Image(option.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.engine.title)
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(isAvailable ? strengths : String(localized: "Unavailable in this build"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("default-engine-\(option.engine.name)")
    }

    private var strengths: String {
        option.benefits.map { String(localized: $0.title) }.formatted(.list(type: .and, width: .narrow))
    }
}
