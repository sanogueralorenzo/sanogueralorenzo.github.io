import SwiftUI

/// Site controls own a dark surface even when their Space uses dark ink: the
/// device's surface material, drawn in its dark appearance so bright page
/// content behind it never washes out the light labels. A color-scheme override
/// alone does not replace an inherited foreground style.
struct BrowserSiteControlPopoverStyle: ViewModifier {
    @Environment(\.crestSurfaceMaterial) private var surfaceMaterial

    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundStyle(Color.white)
            .tint(CrestBrandTheme.accent(.dark))
            .presentationBackground(surfaceMaterial.material)
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
    }
}

#if DEBUG
    #Preview("Dark popover from a light Space") {
        BrowserSiteControlStylePreview()
            .foregroundStyle(Color.black)
            .tint(.black)
            .environment(\.colorScheme, .light)
    }

    #Preview("Dark popover from a dark Space") {
        BrowserSiteControlStylePreview()
            .foregroundStyle(Color.white)
            .environment(\.colorScheme, .dark)
    }

    private struct BrowserSiteControlStylePreview: View {
        @State private var remembersChoice = true

        var body: some View {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                Text("Site Controls").font(.headline)
                Text(verbatim: "example.com").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: CrestSpacing.small) {
                    BrowserSiteQuickActionButton(title: "Copy Link", systemImage: "square.and.arrow.up", action: {})
                    BrowserSiteQuickActionButton(title: "Reload", systemImage: "arrow.clockwise", action: {})
                    BrowserSiteQuickActionButton(title: "Capture", systemImage: "camera", action: {}).disabled(true)
                }
                Divider()
                Label("Secure", systemImage: "lock.fill").foregroundStyle(.green)
                Text("Permissions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    Label("Camera", systemImage: "video").font(.caption)
                    Spacer()
                    Menu("Ask") {
                        Button("Allow") {}
                        Button("Block") {}
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Toggle("Remember in this Space", isOn: $remembersChoice).toggleStyle(.checkbox).font(.caption)
                HStack {
                    Button("Deny") {}.buttonStyle(.bordered)
                    Button("Allow") {}.buttonStyle(.borderedProminent)
                }
            }
            .padding(CrestSpacing.medium)
            .frame(width: BrowserSiteControlMetrics.width)
            .modifier(BrowserSiteControlPopoverStyle())
            .background { CrestSurfaceLayer(shape: Rectangle()).environment(\.colorScheme, .dark) }
            .padding()
            .background(.indigo.gradient)
        }
    }
#endif
