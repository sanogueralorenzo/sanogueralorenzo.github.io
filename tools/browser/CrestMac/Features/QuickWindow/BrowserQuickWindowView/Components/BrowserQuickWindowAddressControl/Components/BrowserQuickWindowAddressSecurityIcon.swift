import SwiftUI

struct BrowserQuickWindowAddressSecurityIcon: View {
    let isSecure: Bool

    var body: some View {
        Image(systemName: isSecure ? "lock.fill" : "magnifyingglass")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Secure and insecure") {
        HStack {
            BrowserQuickWindowAddressSecurityIcon(isSecure: true)
            BrowserQuickWindowAddressSecurityIcon(isSecure: false)
        }.padding()
    }
#endif
