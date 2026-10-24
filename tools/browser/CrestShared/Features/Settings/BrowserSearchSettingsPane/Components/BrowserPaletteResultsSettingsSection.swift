import SwiftUI

/// What the command palette offers and in what order: its layout, whether one
/// best match leads and each row says why it is there, the kinds that show as
/// sections with how many rows each shows and in what order, and the kinds
/// that join them.
struct BrowserPaletteResultsSettingsSection: View {
    @Bindable var preferences: BrowserAppPreferenceStore

    /// The section a person is dragging, while they drag one.
    @State private var dragged: PaletteSource?

    var body: some View {
        Section {
            Picker("Layout", selection: $preferences.palette.layout) {
                ForEach(PaletteLayout.all, id: \.self) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("palette-layout")

            Toggle("Top Hit", isOn: $preferences.palette.showsTopHit)
                .accessibilityIdentifier("palette-top-hit")
            Toggle("Prefer open tabs", isOn: $preferences.palette.prefersOpenTabs)
                .accessibilityIdentifier("palette-prefer-open-tabs")
            Toggle(isOn: $preferences.palette.showsReasons) {
                Text("Show match reasons")
                Text("Notes why each result is there, such as “Often visited” or “Already open”.")
            }
            .accessibilityIdentifier("palette-shows-reasons")
        } header: {
            Text("Results")
        }

        Section {
            ForEach(preferences.palette.sections, id: \.source) { choice in
                sectionRow(for: choice)
            }
            .onMove { offsets, destination in
                preferences.palette = preferences.palette.movingSections(from: offsets, to: destination)
            }
            Button("Reset Order") {
                preferences.palette = preferences.palette.restoringSectionOrder()
            }
            .disabled(preferences.palette.sections.map(\.source) == PalettePreferences.default.sections.map(\.source))
            .accessibilityIdentifier("palette-reset-order")
        } header: {
            Text("Sections")
        } footer: {
            CrestFormFootnote("Drag to change the order.")
        }

        Section("Also show") {
            ForEach(extras, id: \.source) { choice in
                Toggle(isOn: offers(choice.source)) {
                    Text(choice.source.title)
                    if let detail = choice.source.detail {
                        Text(detail)
                    }
                }
                .accessibilityIdentifier("palette-source-\(choice.source.name)")
            }
        }
    }

    /// The kinds that join a section or lead the list, as this platform offers them.
    private var extras: [PaletteSourceChoice] {
        #if os(macOS)
            preferences.palette.extras
        #else
            preferences.palette.extras.filter { $0.source != .pasteAndGo }
        #endif
    }

    // MARK: - Sections

    /// A section's handle and name, how many rows it shows, and whether it shows.
    private func sectionRow(for choice: PaletteSourceChoice) -> some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(choice.source.title)
            Spacer(minLength: CrestSpacing.small)
            Picker("Results shown", selection: limit(of: choice.source)) {
                ForEach(PalettePreferences.limits, id: \.self) { limit in
                    Text("Up to \(limit)").tag(limit)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!choice.isEnabled)
            .accessibilityIdentifier("palette-limit-\(choice.source.name)")
            Toggle(choice.source.title, isOn: offers(choice.source))
                .labelsHidden()
                .accessibilityIdentifier("palette-source-\(choice.source.name)")
        }
        .contentShape(.rect)
        .modifier(
            BrowserPlatformPaletteSectionDrag(source: choice.source, dragged: $dragged) { moving, target in
                preferences.palette = preferences.palette.moving(moving, to: target)
            }
        )
        .accessibilityActions {
            Button("Move Up") { move(choice, by: -1) }
            Button("Move Down") { move(choice, by: 1) }
        }
        .contextMenu {
            Button("Move Up") { move(choice, by: -1) }
                .disabled(choice.source == preferences.palette.sections.first?.source)
            Button("Move Down") { move(choice, by: 1) }
                .disabled(choice.source == preferences.palette.sections.last?.source)
        }
    }

    private func offers(_ source: PaletteSource) -> Binding<Bool> {
        Binding {
            preferences.palette.offers(source)
        } set: { isOn in
            preferences.palette = preferences.palette.offering(source, isOn)
        }
    }

    private func limit(of source: PaletteSource) -> Binding<Int> {
        Binding {
            preferences.palette.limit(of: source)
        } set: { limit in
            preferences.palette = preferences.palette.limiting(source, to: limit)
        }
    }

    private func move(_ choice: PaletteSourceChoice, by offset: Int) {
        guard let index = preferences.palette.sections.firstIndex(where: { $0.source == choice.source }) else { return }
        let destination = offset < 0 ? max(0, index - 1) : min(preferences.palette.sections.count, index + 2)
        preferences.palette = preferences.palette.movingSections(from: IndexSet(integer: index), to: destination)
    }
}
