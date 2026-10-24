import SwiftUI

/// The tab workspace keeps Space selection and Appearance / Details visible
/// while the shared crest editor scrolls below it.
struct MobileSpaceSettingsWorkspaceToolbar: View {
    let browser: BrowserStore
    @Binding var selectedSpaceID: UUID?
    @Binding var section: BrowserSpaceEditorSection

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                identity
                spacePicker
                Spacer(minLength: 0)
                sectionPicker.frame(width: 220)
                spaceOrderControls
                addSpaceButton
            }
            VStack(spacing: 12) {
                HStack {
                    identity
                    Spacer(minLength: 0)
                    spacePicker
                    addSpaceButton
                }
                HStack {
                    sectionPicker
                    Spacer(minLength: CrestSpacing.small)
                    spaceOrderControls
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(BrowserSettingsCanvas.card)
        .accessibilityIdentifier("space-settings-toolbar")
    }

    private var identity: some View {
        HStack(spacing: 8) {
            CrestIconTile(
                systemImage: BrowserSettingsDestination.spaces.symbol,
                color: BrowserSettingsDestination.spaces.color,
                size: 30, symbolSize: 13, cornerRadius: CrestRadius.control
            )
            .accessibilityHidden(true)
            Text("Spaces").font(.headline)
        }
        .fixedSize()
    }

    private var spacePicker: some View {
        Picker("Space", selection: $selectedSpaceID) {
            ForEach(browser.spaceModels) { space in
                BrowserSpaceIdentityLabel(space: space).tag(Optional(space.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .lineLimit(1)
        .accessibilityIdentifier("space-settings-picker")
    }

    private var sectionPicker: some View {
        Picker("Space settings section", selection: $section) {
            ForEach(BrowserSpaceEditorSection.all) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("space-settings-section-picker")
    }

    private var addSpaceButton: some View {
        BrowserSpaceAddButton {
            browser.addSpace()
            selectedSpaceID = browser.selectedSpaceID
        }
    }

    private var spaceOrderControls: some View {
        BrowserSpaceOrderControls(browser: browser, spaceID: selectedSpaceID)
    }
}
