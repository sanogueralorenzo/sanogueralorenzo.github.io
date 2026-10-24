import SwiftUI

struct BrowserSiteSecuritySection: View {
    let page: BrowserPage
    let origin: SiteOrigin
    var reviewCertificate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text(origin.displayName)
                .font(.caption.monospaced())
                .lineLimit(1)
            if canReviewCertificate {
                Button(action: presentCertificate) {
                    HStack(spacing: CrestSpacing.small) {
                        securityLabel
                        Spacer(minLength: CrestSpacing.small)
                        Text("Certificate")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Review Certificate")
                .accessibilityLabel("Review Certificate")
            } else {
                securityLabel
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canReviewCertificate: Bool {
        page.canReviewCertificate
    }

    /// The connection as the core holds it for the page.
    private var security: PageSecurity { page.live.security }

    /// An HTTPS page the engine judged secure but whose verified trust it could
    /// not hand over. Without a certificate to show, the page is not called
    /// secure; the engine's warnings for other states still stand.
    private var isUnconfirmedSecure: Bool {
        security.isSecure
            && page.live.displayURL?.scheme?.lowercased() == "https"
            && !canReviewCertificate
    }

    private var securityLabel: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }

    private var title: LocalizedStringResource {
        isUnconfirmedSecure ? "Connection Details Unavailable" : security.title
    }

    private var symbol: String {
        isUnconfirmedSecure ? "lock" : security.symbol
    }

    private var tint: Color {
        if isUnconfirmedSecure { return .secondary }
        if security.isSecure { return .green }
        return security.isHazardous ? .red : .orange
    }

    private var detail: LocalizedStringResource? { security.detail }

    private func presentCertificate() {
        if let reviewCertificate {
            reviewCertificate()
            return
        }
        page.reviewCertificate()
    }
}
