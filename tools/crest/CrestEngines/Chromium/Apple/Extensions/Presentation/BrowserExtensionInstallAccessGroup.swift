import SwiftUI

struct BrowserExtensionInstallAccessGroup: View {
    let title: String
    let values: [String]
    let emptyText: String
    var choices: Binding<[String: Bool]>?
    var defaultAllowance: (String) -> Bool = { _ in true }

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text("\(title) (\(values.count))")
                .font(.caption.weight(.semibold))
            if values.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    if let choices {
                        Toggle(
                            value,
                            isOn: Binding(
                                get: { choices.wrappedValue[value] ?? defaultAllowance(value) },
                                set: { choices.wrappedValue[value] = $0 }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    } else {
                        Text(value)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
