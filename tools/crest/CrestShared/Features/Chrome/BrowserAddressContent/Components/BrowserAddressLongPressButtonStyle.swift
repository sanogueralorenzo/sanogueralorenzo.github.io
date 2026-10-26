import SwiftUI

struct BrowserAddressLongPressButtonStyle: PrimitiveButtonStyle {
    let action: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .gesture(
                LongPressGesture(
                    minimumDuration: CrestMotion.longPressRecognitionDelay
                )
                .exclusively(before: TapGesture())
                .onEnded { result in
                    switch result {
                    case .first:
                        action()
                    case .second:
                        configuration.trigger()
                    }
                }
            )
            .accessibilityAddTraits(.isButton)
    }
}
