import SwiftUI

struct MobileTransientBrowsingPreviewSurface: View {
    let request: any MobileBrowserTransientRequest

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: CrestSpacing.medium) {
                Image(systemName: request.previewSystemImage)
                    .font(.largeTitle)
                Text(request.accessibilityLabel)
                    .font(.headline)
            }
            .padding(CrestSpacing.extraLarge)
            .background { CrestSurfaceLayer(shape: .rect(cornerRadius: CrestRadius.panel)) }
        }
    }
}
