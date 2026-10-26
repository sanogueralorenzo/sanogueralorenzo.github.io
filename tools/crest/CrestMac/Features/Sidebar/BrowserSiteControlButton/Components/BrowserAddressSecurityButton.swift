import SwiftUI

/// The certificate affordance a live site puts in the address field's leading
/// slot.
///
/// It stays on the windowed shell because it reads a `BrowserPage`'s server
/// trust and hands it to a platform certificate panel — neither of which the
/// compact shell has.
struct BrowserAddressSecurityButton: View {
    let page: BrowserPage
    let isSecure: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: reviewCertificate) {
            BrowserAddressSecurityIcon(isSecure: isSecure)
        }
        .buttonStyle(buttonStyle)
        .foregroundStyle(
            isSecure ? Color(nsColor: .secondaryLabelColor) : Color.red
        )
        .disabled(!canReviewCertificate)
        .accessibilityLabel(stateDescription)
        .accessibilityIdentifier("browser-address-security")
        .help(stateDescription)
        .animation(
            CrestMotion.contentState.unlessReducingMotion(reduceMotion),
            value: isSecure
        )
    }

    private var buttonStyle: CrestChromeButtonStyle {
        CrestChromeButtonStyle(
            controlSize: CGSize(
                width: BrowserSidebarAddressFieldMetrics.securityControlSize,
                height: BrowserSidebarAddressFieldMetrics.securityControlSize
            )
        )
    }

    private var canReviewCertificate: Bool {
        page.canReviewCertificate
    }

    /// The lock speaks for the connection, not for the certificate panel. A
    /// secure page whose server trust WebKit has not published is still secure;
    /// it simply has nothing to review.
    private var stateDescription: LocalizedStringKey {
        guard isSecure else { return "Connection Not Secure" }
        return canReviewCertificate ? "Review Certificate" : "Connection Secure"
    }

    private func reviewCertificate() {
        page.reviewCertificate()
    }
}

private struct BrowserAddressSecurityIcon: View {
    let isSecure: Bool

    var body: some View {
        Image(systemName: isSecure ? "lock.fill" : "lock.open.fill")
            .font(
                .system(
                    size: BrowserTabTrailingControlMetrics.pointer.glyphSize,
                    weight: .medium
                )
            )
            .contentTransition(.symbolEffect(.replace))
            .frame(
                width: BrowserSidebarAddressFieldMetrics.securityControlSize,
                height: BrowserSidebarAddressFieldMetrics.securityControlSize
            )
            .contentShape(.rect)
    }
}
