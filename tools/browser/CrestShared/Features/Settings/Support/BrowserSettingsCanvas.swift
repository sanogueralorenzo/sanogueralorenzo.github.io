import SwiftUI

/// The colors a settings page is drawn on.
enum BrowserSettingsCanvas {
    static var background: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #else
            Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// A raised surface on the page, such as Crest Studio's preview column.
    static var card: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor).mix(with: .primary, by: 0.035)
        #else
            Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

/// Form-like alignment outside a Form: the label leads, the control trails, and
/// the two stack when a narrow column can't hold both on one line.
struct BrowserSettingsLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                configuration.label.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                configuration.content.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 10) {
                configuration.label
                configuration.content.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
