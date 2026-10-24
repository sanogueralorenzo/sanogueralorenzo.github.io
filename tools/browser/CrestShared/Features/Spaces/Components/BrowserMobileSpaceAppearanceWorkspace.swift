#if os(iOS)
    import SwiftUI

    /// A setup draft's touch editor and adaptive preview, in the setup flow's
    /// own paper.
    struct BrowserMobileSpaceAppearanceWorkspace: View {
        @Binding var branding: SpaceBranding
        @Binding var symbol: String
        @Binding var name: String
        var space: BrowserSpaceAppearance? = nil
        var spacePicker: BrowserSpaceCustomizationPicker? = nil
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        var body: some View {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 700 && horizontalSizeClass == .regular
                HStack(alignment: .top, spacing: wide ? 24 : 0) {
                    if wide {
                        preview(compact: false)
                            .frame(width: 260)
                            .frame(maxHeight: 580)
                            .padding(.leading, 24)
                            .padding(.vertical, 20)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !wide { preview(compact: true) }
                            BrowserSpaceBrandingEditor(
                                branding: $branding, symbol: $symbol,
                                previewName: name, compact: !wide, showsPreview: false, editableName: $name)
                        }
                        .padding(wide ? 24 : 20)
                        .frame(maxWidth: 600)
                        .frame(maxWidth: .infinity)
                        .id("mobile-space-appearance-top")
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .background(BrowserOnboardingPalette.parchment)
            .foregroundStyle(BrowserOnboardingPalette.ink)
        }

        private func preview(compact: Bool) -> some View {
            VStack(spacing: 16) {
                if let spacePicker { spacePicker }
                BrowserCrestStudioPreview(
                    branding: branding, symbol: symbol, name: name, space: space, compact: compact)
            }
        }
    }
#endif
