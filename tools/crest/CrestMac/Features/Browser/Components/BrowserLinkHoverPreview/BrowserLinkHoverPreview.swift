import SwiftUI

struct BrowserLinkHoverPreview: View {
    let hover: BrowserLinkHoverController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            if let destination = hover.destination {
                Text(verbatim: destination.text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(hover.isExpanded ? 4 : 1)
                    .truncationMode(hover.isExpanded ? .tail : .middle)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(PreviewMaterial(opaque: reduceTransparency || contrast == .increased))
                    .frame(maxWidth: min(560, max(0, geometry.size.width - 24)), alignment: .leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel("Link destination")
                    .accessibilityValue(Text(verbatim: destination.text))
                    .accessibilityIdentifier("browser-link-hover-preview")
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PreviewMaterial: ViewModifier {
    let opaque: Bool

    func body(content: Content) -> some View {
        if opaque {
            content
                .background(.background, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.primary.opacity(0.5), lineWidth: 1)
                }
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
    }
}
