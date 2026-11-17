import SwiftUI

struct BrowserSpacePill: View {
    let color: Int
    var isSelected = true

    var body: some View {
        Capsule().fill(Color.space(color).opacity(isSelected ? 1 : 0.35))
            .frame(width: 18, height: 6)
    }
}

struct BrowserSpaceColorPicker: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SpaceColors.names.indices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    BrowserSpacePill(color: index)
                        .frame(width: 30, height: 22)
                        .contentShape(Capsule())
                        .overlay {
                            if selection == index { Capsule().stroke(.primary, lineWidth: 1) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SpaceColors.names[index])
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
    }
}
