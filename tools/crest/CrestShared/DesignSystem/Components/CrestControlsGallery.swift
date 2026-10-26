#if DEBUG
    import SwiftUI

    /// Every CrestControls component on one canvas.
    ///
    /// The gallery is the component library's own review surface: a change to a button
    /// role, a field's focus ring, or the selection border shows up here beside every
    /// other control instead of being discovered in whichever pane happened to adopt it.
    /// The previews below cover light, dark, right-to-left, and disabled; selected and
    /// unselected states sit side by side inside the gallery itself.
    ///
    /// Debug-only, and deliberately not wired into any shell.
    struct CrestControlsGallery: View {
        var isEnabled = true

        @State private var placement: TabPlacement = .saved
        @State private var selectedCard = 0
        @State private var chipSelection: UUID? = SessionState.Seed.preview.spaces.first?.id
        @State private var menuSelection: UUID? = SessionState.Seed.preview.spaces.first?.id
        @State private var address = "example.com"
        @State private var name = ""

        private var spaces: [CrestSpaceIdentity] {
            CrestSpaceIdentity.list(SpaceModel.previewSpaces)
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: CrestSpacing.section) {
                    buttons
                    fields
                    segmented
                    cards
                    spacePickers
                    formRows
                }
                .padding(CrestSpacing.extraExtraLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(CrestBrandTheme.canvas)
            .disabled(!isEnabled)
        }

        // MARK: - Sections

        private var buttons: some View {
            section("Buttons") {
                HStack(spacing: CrestSpacing.medium) {
                    Button("Save Setup") {}
                        .buttonStyle(.crestPrimary)
                    Button("Back") {}
                        .buttonStyle(.crestSecondary)
                    Button("Delete") {}
                        .buttonStyle(.crestDestructive)
                }

                HStack(spacing: CrestSpacing.medium) {
                    Button("Manage Filter Lists") {}
                        .buttonStyle(.crestTertiary)
                    Button {
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.crestIcon())
                    .accessibilityLabel("Add site")
                    Button {
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.crestIcon(isProminent: true))
                    .accessibilityLabel("New Space")
                    Button {
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.crestIcon(tint: CrestBrandPalette.sage))
                    .accessibilityLabel("Remove")
                }

                HStack(spacing: CrestSpacing.medium) {
                    Button("Disabled") {}
                        .buttonStyle(.crestPrimary)
                    Button("Disabled") {}
                        .buttonStyle(.crestSecondary)
                    Button {
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.crestIcon(isProminent: true))
                    .accessibilityLabel("Add site")
                }
                .disabled(true)
            }
        }

        private var fields: some View {
            section("Fields") {
                TextField("example.com", text: $address)
                    .crestTextField()
                TextField("Space name", text: $name)
                    .crestTextField()
                TextField("Disabled", text: .constant(""))
                    .crestTextField()
                    .disabled(true)
            }
        }

        private var segmented: some View {
            section("Segmented") {
                Picker("Put new sites in", selection: $placement) {
                    ForEach(TabPlacement.all, id: \.self) { placement in
                        Label(placement.title, systemImage: placement.symbol)
                            .tag(placement)
                    }
                }
                .pickerStyle(.segmented)
                .tint(CrestBrandTheme.accent)

                Picker("Appearance", selection: $placement) {
                    ForEach(TabPlacement.all, id: \.self) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
                .tint(CrestBrandTheme.accent)

                Picker("Disabled", selection: .constant(TabPlacement.pinned)) {
                    ForEach(TabPlacement.all, id: \.self) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
                .tint(CrestBrandTheme.accent)
                .disabled(true)
            }
        }

        private var cards: some View {
            section("Selectable cards") {
                ForEach(0..<2, id: \.self) { index in
                    CrestSelectableCard(
                        isSelected: selectedCard == index,
                        accessibilityLabel: Text(index == 0 ? "Banner" : "Gradient")
                    ) {
                        selectedCard = index
                    } content: {
                        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                            Text(index == 0 ? "Banner" : "Gradient")
                                .font(CrestTypography.displaySection)
                            Text("A patterned band behind the sidebar.")
                                .crestFormFootnote()
                        }
                    }
                }

                CrestSelectableCard(
                    isSelected: true,
                    accessibilityLabel: Text("Disabled"),
                    tint: CrestBrandPalette.sage
                ) {
                } content: {
                    Text("Disabled and selected")
                }
                .disabled(true)
            }
        }

        private var spacePickers: some View {
            section("Space selection") {
                CrestSpaceChipRail(
                    spaces: spaces,
                    selection: $chipSelection,
                    add: CrestSpaceChipAddAction(title: "New Space") {},
                    commands: { identity in
                        [
                            .rename {},
                            .customize {},
                            .delete { _ = identity },
                        ]
                    }
                )

                CrestSpaceMenuPicker(
                    "Default Space",
                    selection: $menuSelection,
                    spaces: spaces
                )

                CrestSpaceMenuPicker(
                    "Space",
                    selection: $menuSelection,
                    spaces: spaces,
                    labelsHidden: true
                )
            }
        }

        private var formRows: some View {
            section("Form rows") {
                Form {
                    Section {
                        CrestFormActionRow(
                            "Manage Filter Lists",
                            subtitle: "Choose which blocklists a Space loads",
                            systemImage: "shield.lefthalf.filled"
                        ) {
                        }

                        CrestFormControlRow(
                            "Default Space",
                            systemImage: "square.grid.2x2",
                            tint: CrestBrandPalette.sky
                        ) {
                            CrestSpaceMenuPicker(
                                "Default Space",
                                selection: $menuSelection,
                                spaces: spaces,
                                labelsHidden: true
                            )
                        }

                        CrestFormControlRow(
                            "Reset All",
                            subtitle: "Makes every site ask again in this Space",
                            systemImage: "arrow.counterclockwise",
                            tint: CrestBrandPalette.coral
                        ) {
                            Button("Reset") {}
                                .buttonStyle(.crestTertiary)
                        }
                    } footer: {
                        CrestFormFootnote(
                            "Startup choices take effect the next time Crest opens a window."
                        )
                    }
                }
                .crestSettingsForm()
                .frame(minHeight: 260)
            }
        }

        // MARK: - Scaffolding

        @ViewBuilder
        private func section<Content: View>(
            _ title: String,
            @ViewBuilder content: () -> Content
        ) -> some View {
            VStack(alignment: .leading, spacing: CrestSpacing.large) {
                Text(verbatim: title)
                    .font(CrestTypography.displayPage)
                    .foregroundStyle(CrestBrandTheme.textDisplay)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
