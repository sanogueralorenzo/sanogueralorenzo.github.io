import SwiftUI

struct BrowserSpaceIdentityEditor: View {
    // MARK: - Variables

    @Binding var name: String
    var color: Binding<SpaceColor>?
    var requestsEditing: Binding<Bool> = .constant(false)
    @FocusState private var isNameFocused: Bool

    // MARK: - Actions - Drawing

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField("Space name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onChange(of: requestsEditing.wrappedValue, initial: true) { _, requested in
                    guard requested else { return }
                    requestsEditing.wrappedValue = false
                    isNameFocused = true
                }
                .accessibilityIdentifier("space-name")
            if let color {
                HStack(spacing: 8) {
                    ForEach(SpaceColor.all, id: \.self) { option in
                        Button {
                            color.wrappedValue = option
                        } label: {
                            Circle()
                                .fill(option.tint.color)
                                .frame(width: 18, height: 18)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if color.wrappedValue == option {
                                        Circle().strokeBorder(CrestBrandTheme.textDisplay, lineWidth: 1)
                                    }
                                }
                        }
                        .buttonStyle(
                            CrestChromeButtonStyle(controlSize: CGSize(width: 28, height: 28), cornerRadius: 14)
                        )
                        .accessibilityLabel(Text(option.title))
                        .accessibilityAddTraits(color.wrappedValue == option ? .isSelected : [])
                        .help(Text(option.title))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Space color")
            }
        }
        .frame(maxWidth: 420)
    }
}
