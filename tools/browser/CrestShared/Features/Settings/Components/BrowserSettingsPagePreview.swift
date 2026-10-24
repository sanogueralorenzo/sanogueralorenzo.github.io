import SwiftUI

/// Local sample content reflows at the chosen zoom without opening a webpage.
struct BrowserSettingsPagePreview: View {
    var zoom: Double = 1

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 10) {
                Text("Sample page")
                    .font(.system(size: 18, weight: .semibold))
                Text("A little room to read")
                    .font(.system(size: 14, weight: .medium))
                Text("Text and images grow together. Choose a comfortable size for your everyday browsing.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                RoundedRectangle(cornerRadius: 6)
                    .fill(.blue.opacity(0.16))
                    .frame(height: 36)
            }
            .padding(16)
            .frame(width: geometry.size.width / zoom, alignment: .topLeading)
            .scaleEffect(zoom, anchor: .topLeading)
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .frame(height: 170)
        .background(Color(white: 0.98))
        .clipped()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page preview")
        .accessibilityValue(CGFloat(zoom).pageZoomPercentage)
    }
}
