import SwiftUI
import UIKit

/// A native color picker with a full swatch-sized touch target and live updates.
struct PlatformSpacePaletteColorWell: View {
    @Binding var selection: Color
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            RoundedRectangle(cornerRadius: 12)
                .fill(selection)
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.18))
                }
                .overlay {
                    Image(systemName: "eyedropper")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.25), in: .circle)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            NativePalettePicker(selection: $selection)
                .overlay(alignment: .topTrailing) {
                    Button("Done") { isPresented = false }
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                }
        }
    }
}

private struct NativePalettePicker: UIViewControllerRepresentable {
    @Binding var selection: Color
    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(selection)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
        context.coordinator.selection = $selection
        let color = UIColor(selection)
        if picker.selectedColor != color { picker.selectedColor = color }
    }
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var selection: Binding<Color>
        init(selection: Binding<Color>) { self.selection = selection }
        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            selection.wrappedValue = Color(uiColor: viewController.selectedColor)
        }
    }
}

#if DEBUG
    #Preview("Choose a color") {
        @Previewable @State var color: Color = .indigo
        PlatformSpacePaletteColorWell(selection: $color).padding()
    }
#endif
