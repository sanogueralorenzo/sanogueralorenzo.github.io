import SwiftUI

struct BrowserCredentialSearchField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(title, text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    text = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, CrestSpacing.small)
        #if os(macOS)
            .frame(height: 30)
        #else
            .frame(minHeight: 44)
        #endif
        .background(.quaternary, in: .rect(cornerRadius: CrestRadius.control))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

#if DEBUG
    #Preview("Interactive search") {
        @Previewable @State var query = ""
        BrowserCredentialSearchField(
            title: "Search Passwords", text: $query, accessibilityIdentifier: "preview-password-search"
        )
        .padding().frame(width: 360)
    }
#endif
