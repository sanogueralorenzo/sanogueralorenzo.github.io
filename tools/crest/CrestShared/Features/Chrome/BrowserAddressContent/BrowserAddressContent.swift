import SwiftUI

struct BrowserAddressContent: View {
    // MARK: - Static Variables

    /// The room a text field keeps around its text, which the centered text
    /// needs beyond its own width.
    private static let textInset: CGFloat = 8

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
    /// The field the address centers its text in, when controls on one side
    /// of the address outweigh those on the other. Without it the text centers
    /// between the controls beside it.
    var centeringField: NamedCoordinateSpace?
    let submit: () -> Void

    @FocusState private var isFocused: Bool
    @State private var selection: TextSelection?
    /// How much farther the field reaches past the address's leading edge
    /// than past its trailing edge.
    @State private var fieldImbalance: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var textWidth: CGFloat = 0

    var body: some View {
        Group {
            if isEditing || isFocused {
                addressEditor
            } else {
                addressSummary
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { proxy in
            guard let centeringField, let field = proxy.bounds(of: centeringField) else { return 0 }
            return proxy.size.width - field.minX - field.maxX
        } action: {
            fieldImbalance = $0
        }
        // Only an address that centers in a field measures itself; the others
        // keep their layout free of width and text-width state.
        .onGeometryChange(for: CGFloat.self) { proxy in
            centeringField == nil ? 0 : proxy.size.width
        } action: {
            width = $0
        }
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
        centeredInField(
            TextField(
                prompt,
                text: $text,
                selection: $selection
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center),
            measuring: text.isEmpty ? Text(prompt) : Text(verbatim: text)
        )
        #if os(iOS)
            // A combined search and address field keeps the ordinary space
            // bar, which URL keyboards remove.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.default)
            .submitLabel(.go)
        #endif
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
            centeredInField(
                addressSummaryLabel(presentation),
                measuring: addressSummaryLabel(presentation)
            )
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
    }

    private func addressSummaryLabel(
        _ presentation: BrowserAddressPresentation
    ) -> some View {
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
    }

    // MARK: - Actions - Centering

    /// Gives the field's imbalance back on the address's shorter side, so the
    /// text, measured from `label`, sits at the center of the field rather
    /// than of the space between the controls. Text too wide for that keeps
    /// the room it needs.
    @ViewBuilder
    private func centeredInField(
        _ content: some View,
        measuring label: some View
    ) -> some View {
        if centeringField == nil {
            content
        } else {
            content
                .padding(.leading, max(0, -centeringOffset))
                .padding(.trailing, max(0, centeringOffset))
                .background {
                    label
                        .fixedSize()
                        .hidden()
                        .accessibilityHidden(true)
                        .onGeometryChange(for: CGFloat.self, of: \.size.width) { textWidth = $0 }
                }
        }
    }

    /// The padding that centers the text in the field: positive on the
    /// trailing side, negative on the leading side.
    private var centeringOffset: CGFloat {
        let room = max(0, width - textWidth - Self.textInset)
        let offset = min(abs(fieldImbalance), room)
        return fieldImbalance < 0 ? -offset : offset
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
