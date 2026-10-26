import SwiftUI

/// Making a Space yours: the Space as its sidebar beside a page, its name
/// edited there, and one sheet of what the look lets a first run change. The
/// full Forge waits in Settings.
struct BrowserOnboardingMakePage: View {
    let look: SetupLook
    @Binding var branding: SpaceBranding
    @Binding var symbol: String
    @Binding var name: String
    /// The Space as its icon draws it, for the page beside the sidebar.
    let identity: BrowserSpaceIdentity
    /// The Spaces being made, as chips, or nil for a page that makes one
    /// Space alone.
    var picker: BrowserOnboardingMakePicker? = nil
    /// Why the last edit was refused, when it was.
    var failure: BrowserOnboardingFailureText? = nil
    let back: BrowserOnboardingBackAction?
    let advanceTitle: Text
    let advance: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let inset = BrowserOnboardingStageMetrics.pageInset(for: geometry.size.width)
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 20) {
                    BrowserOnboardingHeadline("Make it yours")
                    Spacer()
                    if look.kind == .heraldic {
                        Button("Shuffle", systemImage: "shuffle") {
                            branding = BrowserCrestForge.shuffled(branding)
                        }
                        .buttonStyle(.crestSecondary)
                        .help("A new crest and sidebar for this Space")
                        .accessibilityIdentifier("space-forge-shuffle")
                    }
                    if let picker {
                        BrowserOnboardingMakeChips(picker: picker)
                    }
                }
                .padding(.horizontal, inset)
                .padding(.top, 8)
                .padding(.bottom, 20)

                GeometryReader { body in
                    HStack(alignment: .top, spacing: BrowserOnboardingMakeMetrics.spacing) {
                        preview
                            .frame(width: previewWidth(in: body.size.width), height: body.size.height)
                        sheet
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, inset)
                .padding(.bottom, 8)

                BrowserOnboardingFooter(back: back) {
                    HStack(spacing: 22) {
                        if let failure {
                            BrowserOnboardingFailureMessage(message: failure)
                                .font(CrestTypography.sans(12, weight: .medium))
                                .foregroundStyle(.red)
                                .lineLimit(2)
                                .accessibilityIdentifier("onboarding-workflow-error")
                        }
                        BrowserOnboardingContinueButton(advanceTitle, action: advance)
                            .accessibilityIdentifier("space-setup-continue")
                    }
                }
            }
        }
    }

    /// The width the window takes of `available`: under half, and never
    /// narrower than its sidebar and a page beside it.
    private func previewWidth(in available: CGFloat) -> CGFloat {
        max(BrowserOnboardingMakeMetrics.minimumPreviewWidth, available * 0.44)
    }

    /// The Space as its window, its icon large on the page.
    private var preview: some View {
        BrowserOnboardingWindowPreview(
            branding: branding, symbol: symbol, name: name, editableName: $name, showsNameHint: true
        ) {
            BrowserSpaceIdentityIcon(identity: identity, size: BrowserOnboardingMakeMetrics.pageIconSize)
                .frame(
                    width: BrowserOnboardingMakeMetrics.pageIconSize, height: BrowserOnboardingMakeMetrics.pageIconSize)
        }
    }

    @ViewBuilder private var sheet: some View {
        switch look.kind {
        case .heraldic:
            BrowserOnboardingHeraldicSheet(branding: $branding, symbol: $symbol)
        case .modern:
            BrowserOnboardingModernSheet(branding: $branding, symbol: $symbol)
        }
    }
}

/// The Spaces a page makes, as chips with one to add.
struct BrowserOnboardingMakePicker {
    let spaces: [BrowserSpaceIdentity]
    let selectedID: UUID?
    let select: (UUID) -> Void
    let add: () -> Void
    /// Removes a Space the setup made, or nil for one it cannot remove.
    let remove: (UUID) -> (() -> Void)?
}

private struct BrowserOnboardingMakeChips: View {
    let picker: BrowserOnboardingMakePicker

    /// The chips in a row where they fit the header, and in a row that
    /// scrolls sideways where a setup has made more Spaces than fit.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips
            ScrollView(.horizontal) { chips }
                .scrollIndicators(.hidden)
                .frame(maxWidth: BrowserOnboardingMakeMetrics.chipsWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(picker.spaces) { space in
                BrowserOnboardingSpaceChip(space: space, isSelected: space.id == picker.selectedID) {
                    picker.select(space.id)
                }
                .contextMenu {
                    if let remove = picker.remove(space.id) {
                        Button("Remove Space", role: .destructive, action: remove)
                    }
                }
            }
            Button(action: picker.add) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CrestBrandTheme.textDisplay)
                    .frame(width: 34, height: 34)
                    .background(CrestBrandPalette.paper.opacity(0.1), in: .circle)
                    .overlay { Circle().strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help("New Space")
            .accessibilityLabel("Add a Space")
            .accessibilityIdentifier("space-customization-add")
        }
    }
}

/// One Space as a chip: its icon and name, lit when it is the one shown.
struct BrowserOnboardingSpaceChip: View {
    let space: BrowserSpaceIdentity
    let isSelected: Bool
    let select: () -> Void

    init(space: some BrowserSpaceIdentifying, isSelected: Bool, select: @escaping () -> Void) {
        self.space = space.identity
        self.isSelected = isSelected
        self.select = select
    }

    var body: some View {
        Button(action: select) {
            BrowserSpaceIdentityLabel(identity: space, iconSize: 18)
                .font(CrestTypography.sans(13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? CrestBrandPalette.ink : CrestBrandTheme.textDisplay)
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .frame(height: 34)
                .background(isSelected ? CrestBrandPalette.paper : CrestBrandPalette.paper.opacity(0.1), in: .capsule)
                .overlay {
                    Capsule().strokeBorder(CrestBrandTheme.line, lineWidth: isSelected ? 0 : CrestLayout.hairline)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum BrowserOnboardingMakeMetrics {
    /// The window never narrows past its sidebar and a page beside it.
    static let minimumPreviewWidth: CGFloat = 520
    /// Between the window and the sheet.
    static let spacing: CGFloat = 48
    /// The most of the header the Space chips take once they scroll.
    static let chipsWidth: CGFloat = 520
    static let pageIconSize: CGFloat = 180
    /// A choice tile on the sheet.
    static let tileSize: CGFloat = 52
    static let tileArtworkSize: CGFloat = 40
    static let swatchSize: CGFloat = 34
}
