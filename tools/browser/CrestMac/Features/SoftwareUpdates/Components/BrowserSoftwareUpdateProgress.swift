import SwiftUI

struct BrowserSoftwareUpdateProgress: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Software update progress")
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSoftwareUpdateProgress(progress: 0.64).padding().frame(width: 420)
    }
#endif
