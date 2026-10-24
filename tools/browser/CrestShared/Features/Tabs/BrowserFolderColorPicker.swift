import SwiftUI

struct BrowserFolderColorPicker: View {
    @Binding var color: BrandColor
    var title: LocalizedStringKey = "Folder Color"
    var showsReset = false
    var resetTitle: LocalizedStringKey? = nil
    var reset: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(
        repeating: GridItem(.fixed(28), spacing: CrestSpacing.small),
        count: 6
    )

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            HStack(spacing: CrestSpacing.small) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsReset, let resetTitle, let reset {
                    Button(action: reset) {
                        Image(systemName: "trash")
                            .frame(
                                width: CrestLayout.minimumHitTarget,
                                height: CrestLayout.minimumHitTarget
                            )
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
                    .help(Text(resetTitle))
                    .accessibilityLabel(Text(resetTitle))
                    .accessibilityIdentifier("browser-color-picker-reset")
                }
            }

            LazyVGrid(columns: columns, spacing: CrestSpacing.small) {
                ForEach(BrowserFolderColorPalette.choices) { choice in
                    Button {
                        color = choice.value
                    } label: {
                        Circle()
                            .fill(choice.value.color)
                            .frame(width: 22, height: 22)
                            .padding(3)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        Color.primary.opacity(
                                            color == choice.value ? 0.75 : 0.14
                                        ),
                                        lineWidth: color == choice.value ? 2 : 0.5
                                    )
                            }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .help(choice.title)
                    .accessibilityLabel(choice.title)
                    .accessibilityValue(
                        color == choice.value ? "Selected" : ""
                    )
                }
            }

            Divider()

            ColorPicker(
                "Custom Color",
                selection: Binding(
                    get: { color.color },
                    set: { color = BrandColor(color: $0) }
                ),
                supportsOpacity: false
            )
        }
        .padding(CrestSpacing.large)
        .frame(width: 246)
        .animation(resetAnimation, value: showsReset)
    }

    private var resetAnimation: Animation? {
        CrestMotion.collection.unlessReducingMotion(reduceMotion)
    }
}
