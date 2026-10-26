import SwiftUI

/// A keyboard-reachable choice card with shared selection, hover, press, and
/// accessibility behavior. Callers own only the card's content.
struct CrestSelectableCard<Content: View>: View {
    let isSelected: Bool
    let accessibilityLabel: Text
    var tint: Color?
    var showsCheckmark = true
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        isSelected: Bool,
        accessibilityLabel: Text,
        tint: Color? = nil,
        showsCheckmark: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isSelected = isSelected
        self.accessibilityLabel = accessibilityLabel
        self.tint = tint
        self.showsCheckmark = showsCheckmark
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: CrestSelectableCardMetrics.contentSpacing) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsCheckmark {
                    checkmark
                }
            }
        }
        .buttonStyle(
            CrestSelectableCardStyle(isSelected: isSelected, tint: tint)
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var checkmark: some View {
        Image(systemName: CrestSelectableCardMetrics.checkmarkSymbol)
            .font(.system(size: CrestSelectableCardMetrics.checkmarkSize))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint ?? CrestBrandTheme.accent)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Interactive selection") {
        @Previewable @State var selected = 0
        VStack {
            ForEach(0..<2) { index in
                CrestSelectableCard(
                    isSelected: selected == index, accessibilityLabel: Text(index == 0 ? "Banner" : "Gradient"),
                    action: { selected = index }
                ) {
                    Label(
                        index == 0 ? "Banner" : "Gradient",
                        systemImage: index == 0 ? "flag.fill" : "circle.lefthalf.filled"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.padding().frame(width: 360)
    }
#endif
