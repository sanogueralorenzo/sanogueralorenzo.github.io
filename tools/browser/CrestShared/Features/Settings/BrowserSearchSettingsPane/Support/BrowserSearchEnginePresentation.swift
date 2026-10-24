import SwiftUI

enum BrowserSpaceBrowsingPickerPresentationStyle {
    case nativePicker
    case paddedMenu
}

enum BrowserSearchEngineEditorPresentationStyle {
    case navigation
    case sheet
}

struct BrowserSearchEngineSheetSize {
    let minimumWidth: CGFloat
    let minimumHeight: CGFloat

    static let manager = Self(minimumWidth: 480, minimumHeight: 460)
    static let editor = Self(minimumWidth: 440, minimumHeight: 360)
}

extension View {
    @ViewBuilder
    func browserSearchEngineEditorPresentation<Item: Hashable & Identifiable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        switch BrowserPlatformSearchEnginePresentation.editorStyle {
        case .navigation:
            navigationDestination(item: item, destination: destination)
        case .sheet:
            sheet(item: item) { item in
                NavigationStack {
                    destination(item)
                }
                .browserSearchEngineSheetSizing(.editor)
            }
        }
    }

    func browserSearchEngineSheetSizing(_ size: BrowserSearchEngineSheetSize) -> some View {
        modifier(BrowserPlatformSearchEngineSheetSizingModifier(size: size))
    }
}
