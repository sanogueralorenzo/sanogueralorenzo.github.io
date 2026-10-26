import SwiftUI

struct BrowserStrongPasswordActionButton: View {
    let isWorking: Bool
    let tint: Color
    let metrics: BrowserCredentialPromptMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .frame(
                        minWidth: metrics.actionMinimumWidth,
                        maxWidth: metrics.actionMaximumWidth,
                        minHeight: BrowserCredentialPromptMetrics.controlHitTarget
                    )
                    .accessibilityLabel("Creating strong password")
            } else {
                Label(
                    "Use Strong Password",
                    systemImage: "key.horizontal.fill"
                )
                .frame(
                    minWidth: metrics.actionMinimumWidth,
                    maxWidth: metrics.actionMaximumWidth,
                    minHeight: BrowserCredentialPromptMetrics.controlHitTarget
                )
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(isWorking)
    }
}

#if DEBUG
    #Preview("Ready and working") {
        VStack(spacing: 20) {
            BrowserStrongPasswordActionButton(isWorking: false, tint: .indigo, metrics: .pointer, action: {})
            BrowserStrongPasswordActionButton(isWorking: true, tint: .indigo, metrics: .touch, action: {})
        }.padding().frame(width: 380)
    }
#endif
