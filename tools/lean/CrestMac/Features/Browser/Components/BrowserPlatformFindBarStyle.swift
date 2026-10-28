import SwiftUI

/// macOS floats the find bar as a bordered panel over the page, with the
/// window's own borderless controls inside it.
struct BrowserPlatformFindBarStyle: ViewModifier {
    private static let cornerRadius: CGFloat = 10
    private static let strokeWidth: CGFloat = 0.5

    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderless)
            .controlSize(.small)
            .background(
                .background,
                in: .rect(cornerRadius: Self.cornerRadius)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: Self.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(.separator, lineWidth: Self.strokeWidth)
            }
    }
}
