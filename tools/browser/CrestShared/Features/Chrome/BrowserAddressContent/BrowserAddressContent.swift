import SwiftUI

struct BrowserAddressContent: View {
    // MARK: - Variables

    @Binding var text: String
    @Binding var isEditing: Bool
    var focusRequest = 0
    var activate: (() -> Void)?
    var longPressAction: (() -> Void)?
    var editorAccessibilityLabel: LocalizedStringKey = "Address and search"
    var editorAccessibilityIdentifier = "address-field"
    var summaryAccessibilityIdentifier = "address-display"
    var prompt: LocalizedStringKey = "Search or enter website"
    let submit: () -> Void

    @FocusState private var isFocused: Bool
    @State private var selection: TextSelection?

    var body: some View {
        Group {
            if isEditing || isFocused {
                addressEditor
            } else {
                addressSummary
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: isFocused, initial: true) { _, focused in
            if focused { selectAllOnceFocused() }
            guard isEditing != focused else { return }
            isEditing = focused
        }
        .onChange(of: isEditing) { _, editing in
            guard editing != isFocused else { return }
            if editing {
                focusAndSelectAll()
            } else {
                isFocused = false
            }
        }
        .onChange(of: focusRequest, initial: true) { _, request in
            guard request > 0 else { return }
            isEditing = true
            focusAndSelectAll()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: BrowserAddressFocusDismissal.notification
            )
        ) { _ in
            isEditing = false
            isFocused = false
        }
    }

    private var addressEditor: some View {
        TextField(
            prompt,
            text: $text,
            selection: $selection
        )
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .modifier(BrowserPlatformAddressInputModifier())
        .focused($isFocused)
        .onSubmit(submit)
        // Escape puts the address away without opening it, as a click
        // elsewhere does.
        .onKeyPress(.escape) {
            isFocused = false
            return .handled
        }
        .onTapGesture(perform: selectAll)
        .accessibilityLabel(Text(editorAccessibilityLabel))
        .accessibilityIdentifier(editorAccessibilityIdentifier)
    }

    private var addressSummary: some View {
        let presentation = BrowserAddressPresentation(text)

        return Group {
            if let longPressAction {
                addressSummaryButton(presentation)
                    .buttonStyle(
                        BrowserAddressLongPressButtonStyle(
                            action: longPressAction
                        )
                    )
                    .accessibilityAction(named: "New Tab", longPressAction)
            } else {
                addressSummaryButton(presentation)
                    .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(
            text.isEmpty ? "Address and search" : "Address, \(text)"
        )
        .accessibilityValue(text)
        .accessibilityHint(
            activate == nil
                ? "Opens the address field for editing"
                : "Opens the command palette"
        )
        .accessibilityIdentifier(summaryAccessibilityIdentifier)
    }

    // MARK: - Actions - Address summary

    private func addressSummaryButton(
        _ presentation: BrowserAddressPresentation
    ) -> some View {
        Button {
            if let activate {
                activate()
            } else {
                isEditing = true
                focusAndSelectAll()
            }
        } label: {
            VStack(spacing: -1) {
                Text(presentation.domain)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let route = presentation.route {
                    Text(route)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
    }

    // MARK: - Actions - Selection

    private func focusAndSelectAll() {
        Task { @MainActor in
            await Task.yield()
            isFocused = true
            selectAll()
        }
    }

    /// UIKit moves the caret to the end when the field takes focus, so the
    /// selection has to land after that.
    private func selectAllOnceFocused() {
        Task { @MainActor in
            await Task.yield()
            selectAll()
        }
    }

    private func selectAll() {
        guard !text.isEmpty else { return }
        selection = TextSelection(range: text.startIndex..<text.endIndex)
    }
}

#if DEBUG
    #Preview("Editable address") {
        @Previewable @State var text = "crestbrowser.com"
        @Previewable @State var editing = false
        BrowserAddressContent(text: $text, isEditing: $editing, submit: { editing = false })
            .padding().frame(width: 320)
    }
#endif
