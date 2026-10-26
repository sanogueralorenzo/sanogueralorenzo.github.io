import SwiftUI

struct BrowserPlatformEmojiVariantModifier: ViewModifier {
    let choice: BrowserTabEmojiChoice
    @Binding var isPresented: Bool
    let selectEmoji: (String) -> Void

    func body(content: Content) -> some View {
        content
            .buttonStyle(BrowserEmojiVariantButtonStyle { isPresented = true })
            .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds)) {
                BrowserEmojiVariantPicker(variants: choice.variants, selectEmoji: selectEmoji)
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityAction(named: "Show Emoji Variations") { isPresented = true }
            .accessibilityHint("Long press to choose a skin tone variation.")
    }
}

private struct BrowserEmojiVariantButtonStyle: PrimitiveButtonStyle {
    private static let longPressDuration = 0.45
    let showVariants: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .gesture(
                LongPressGesture(minimumDuration: Self.longPressDuration)
                    .exclusively(before: TapGesture())
                    .onEnded { value in
                        switch value {
                        case .first: showVariants()
                        case .second: configuration.trigger()
                        }
                    })
    }
}
