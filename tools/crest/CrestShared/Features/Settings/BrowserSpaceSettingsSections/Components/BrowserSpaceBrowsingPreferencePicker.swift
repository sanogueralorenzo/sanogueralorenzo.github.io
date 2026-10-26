import SwiftUI

struct BrowserSpaceBrowsingPreferencePicker<Choice: Identifiable & Hashable, ChoiceLabel: View, SelectedValue: View>:
    View
{
    let title: LocalizedStringKey
    let presentation: BrowserSpaceBrowsingPickerPresentationStyle
    @Binding var selection: Choice
    let choices: [Choice]
    let choiceTitle: (Choice) -> String
    let accessibilityIdentifier: String
    let dismissKeyboard: @MainActor () -> Void
    @ViewBuilder let choiceLabel: (Choice) -> ChoiceLabel
    @ViewBuilder let selectedValue: () -> SelectedValue

    @State private var keyboardDismissal = BrowserSearchEngineKeyboardDismissal()

    var body: some View {
        picker.onDisappear { keyboardDismissal.cancel() }
    }

    @ViewBuilder
    private var picker: some View {
        switch presentation {
        case .nativePicker:
            Picker(title, selection: $selection) {
                ForEach(choices) { choice in
                    choiceLabel(choice).tag(choice)
                }
            }
            .accessibilityIdentifier(accessibilityIdentifier)
        case .paddedMenu:
            Menu {
                ForEach(choices) { choice in
                    Button {
                        selection = choice
                        dismissKeyboard()
                        keyboardDismissal.schedule(dismissKeyboard)
                    } label: {
                        Label {
                            Text(choiceTitle(choice))
                        } icon: {
                            if choice.id == selection.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                BrowserSpaceBrowsingMenuLabel(title: title, layout: .touch, value: selectedValue)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(choiceTitle(selection))
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}
