#if CREST_CHROMIUM_HOST
    import AppKit
    import SwiftUI
    import Translation

    /// Selection translation for the Chromium host.
    ///
    /// Beside whole-page translation, a page's context menu translates the passage
    /// a person selected. It is Apple's on-device translation either way: the same
    /// system service, the same language downloads, and nothing sent to a
    /// translation server.
    ///
    /// The presentation is anchored to a one-point view added to the key window, which
    /// is what Apple's translation presentation wants and what lets the popover follow
    /// the window it belongs to. Nothing is retained after it closes.
    @MainActor
    enum ChromiumSelectionTranslation {
        /// A selection long enough to exceed this is a page, not a passage.
        private static let maximumLength = 4096
        private static var anchor: NSView?

        static func present(_ text: String) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, let contentView = NSApp.keyWindow?.contentView else { return }
            dismiss()
            let view = NSHostingView(
                rootView: SelectionTranslationAnchor(
                    text: String(value.prefix(maximumLength)),
                    dismiss: dismiss
                )
            )
            view.frame = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
            contentView.addSubview(view)
            anchor = view
        }

        static func dismiss() {
            anchor?.removeFromSuperview()
            anchor = nil
        }
    }

    private struct SelectionTranslationAnchor: View {
        let text: String
        let dismiss: @MainActor () -> Void

        @State private var isPresented = false

        var body: some View {
            Color.clear
                .frame(width: 1, height: 1)
                .translationPresentation(isPresented: $isPresented, text: text)
                .onAppear { isPresented = true }
                .onChange(of: isPresented) { _, presented in
                    if !presented { dismiss() }
                }
        }
    }
#endif
