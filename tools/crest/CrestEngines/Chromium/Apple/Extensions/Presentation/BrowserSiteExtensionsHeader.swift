import SwiftUI

struct BrowserSiteExtensionsHeader: View {
    let manageExtensions: () -> Void

    var body: some View {
        HStack {
            Text("Extensions")
                .font(.headline)
            Spacer(minLength: CrestSpacing.small)
            Button(action: manageExtensions) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(
                CrestChromeButtonStyle(
                    controlSize: CGSize(
                        width: BrowserSiteControlMetrics.manageExtensionControlSize,
                        height: BrowserSiteControlMetrics.manageExtensionControlSize
                    ),
                    cornerRadius: 6,
                    showsRestingFill: true
                )
            )
            .accessibilityLabel("Manage Extensions")
            .help("Manage Extensions")
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSiteExtensionsHeader(manageExtensions: {}).padding().frame(width: 340)
    }
#endif
