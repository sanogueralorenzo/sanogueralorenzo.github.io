import SwiftUI

/// One option of a built-in provider, beneath it in Settings, drawn as the
/// option describes itself: a switch, a menu of its choices, a menu of
/// languages, regions or stores that starts as Automatic, or a field for text
/// that adds nothing while it is empty.
struct BrowserSearchProviderOptionRow: View {
    let option: SearchProviderOption
    let provider: BuiltInSearchProvider
    let catalog: BrowserSearchCatalog

    @State private var text = ""
    @FocusState private var textIsFocused: Bool

    var body: some View {
        Group {
            if option.isSwitch {
                Toggle(isOn: switchValue) { Text(option.title) }
            } else if option.acceptsText {
                LabeledContent {
                    TextField(option.title, text: $text, prompt: option.textExample.map { Text(verbatim: $0) })
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                        .focused($textIsFocused)
                        .onSubmit(commitText)
                } label: {
                    Text(option.title)
                }
                .onAppear { text = currentValue ?? "" }
                .onChange(of: textIsFocused) { _, isFocused in
                    if !isFocused { commitText() }
                }
            } else {
                Picker(selection: menuValue) {
                    if !option.locales.isEmpty {
                        Text("Automatic").tag(String?.none)
                    }
                    ForEach(Array(option.choices.enumerated()), id: \.element) { index, choice in
                        Text(choice.title).tag(index == 0 ? String?.none : Optional(choice.name))
                    }
                    ForEach(option.locales, id: \.code) { code in
                        Text(verbatim: placeTitle(code)).tag(Optional(code.code))
                    }
                } label: {
                    Text(option.title)
                }
            }
        }
        .padding(.leading, BrowserSearchProviderOptionRowMetrics.indent)
        .accessibilityIdentifier("search-option-\(option.name)")
    }

    private var currentValue: String? {
        catalog.value(of: option, for: provider)
    }

    private var switchValue: Binding<Bool> {
        Binding {
            currentValue == SearchProviderOption.on
        } set: { isOn in
            catalog.setOption(option, of: provider, to: isOn ? SearchProviderOption.on : nil)
        }
    }

    private var menuValue: Binding<String?> {
        Binding {
            currentValue
        } set: {
            catalog.setOption(option, of: provider, to: $0)
        }
    }

    private func commitText() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed != (currentValue ?? "") else { return }
        catalog.setOption(option, of: provider, to: trimmed.isEmpty ? nil : trimmed)
    }

    /// A place as this device names it: its region for a country or store,
    /// else its language and region.
    private func placeTitle(_ code: SearchLocaleCode) -> String {
        let locale = Locale(identifier: code.locale)
        if option.namesRegions, let region = locale.region,
            let name = Locale.current.localizedString(forRegionCode: region.identifier)
        {
            return name
        }
        return Locale.current.localizedString(forIdentifier: code.locale) ?? code.code
    }
}

/// Where an option starts beneath its provider: under the provider's name,
/// past its chevron and icon.
enum BrowserSearchProviderOptionRowMetrics {
    static let chevronWidth: CGFloat = 10
    static let iconSize: CGFloat = 20
    static let indent: CGFloat = chevronWidth + iconSize + 2 * CrestSpacing.small
}
