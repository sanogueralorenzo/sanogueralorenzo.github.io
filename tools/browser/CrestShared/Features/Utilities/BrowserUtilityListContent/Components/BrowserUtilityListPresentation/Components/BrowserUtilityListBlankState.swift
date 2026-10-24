import SwiftUI

struct BrowserUtilityListBlankState: View {
    let dismiss: (() -> Void)?

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {
                    dismiss?()
                }
                .accessibilityHidden(true)

            ProgressView("Loading…")
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
