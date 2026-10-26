import SwiftUI

struct BrowserTranslationMenu: View {
    let translation: BrowserPageTranslation

    var body: some View {
        Menu {
            BrowserTranslationActions(translation: translation)
                .crestMenuActionLabelStyle()
        } label: {
            Image(systemName: "translate")
                .foregroundStyle(translation.isTranslated ? Color.accentColor : .primary)
                .overlay(alignment: .topTrailing) {
                    if translation.isWorking {
                        ProgressView().controlSize(.mini).offset(x: 6, y: -5)
                    } else if translation.isTranslated {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 6, y: -5)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .accessibilityLabel("Translate Page")
        .accessibilityValue(translation.status)
        .accessibilityAction(named: "Translate Now", translation.start)
        .accessibilityIdentifier("page-translation-menu")
    }
}

struct BrowserTranslationActions: View {
    let translation: BrowserPageTranslation
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    private var automaticallyTranslatesSource: Binding<Bool> {
        Binding {
            preferences.automaticallyTranslates
                && preferences.preferences.translationRules.decision(for: translation.sourceID)?.target != nil
        } set: { enabled in
            preferences.setTranslationRule(
                sourceID: translation.sourceID, targetID: translation.targetID, isEnabled: enabled)
            if enabled { preferences.automaticallyTranslates = true }
        }
    }

    var body: some View {
        if !translation.status.isEmpty { Text(translation.status) }
        BrowserTranslationLanguagePickers(translation: translation)
            .pickerStyle(.menu)
        if translation.isWorking {
            Button("Cancel Translation", systemImage: "stop.circle", action: { translation.cancel() })
        } else {
            Button(
                translation.isTranslated
                    ? String(localized: "Translate Page Again") : String(localized: "Translate Page"),
                systemImage: "translate", action: translation.start
            )
            .disabled(!translation.canTranslate)
        }
        if translation.isTranslated {
            Button("Show Original", systemImage: "arrow.uturn.backward", action: translation.showOriginal)
        }
        Divider()
        if !translation.sourceID.isEmpty {
            Toggle(isOn: automaticallyTranslatesSource) {
                Label(
                    "Always Translate \(translation.languageName(translation.sourceID))",
                    systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(
                translation.targetID.isEmpty
                    || BrowserTranslationLanguageCatalog.matches(translation.sourceID, translation.targetID))
        }
        Toggle("Offer to Translate", isOn: $preferences.offersTranslation)
        Button("Download More Languages…", systemImage: "arrow.down.circle") { translation.showsInformation = true }
        Button("About Page Translation", systemImage: "info.circle") { translation.showsInformation = true }
    }
}

struct BrowserTranslationLanguagePickers: View {
    @Bindable var translation: BrowserPageTranslation

    var body: some View {
        sourcePicker
        targetPicker
    }

    var sourcePicker: some View {
        Picker(selection: $translation.sourceID) {
            Label("Detect Language", systemImage: "text.magnifyingglass").tag("")
            // Keep a detected language represented while the supported list loads.
            if !translation.sourceID.isEmpty,
                !translation.languages.contains(where: { $0.minimalIdentifier == translation.sourceID })
            {
                languageLabel(translation.sourceID).tag(translation.sourceID)
            }
            languageChoices
        } label: {
            Label("From", systemImage: "text.magnifyingglass")
        }
        .crestMenuActionLabelStyle()
        .disabled(translation.isWorking)
    }

    var targetPicker: some View {
        Picker(selection: $translation.targetID) {
            if translation.targetID.isEmpty {
                Label("Loading Languages…", systemImage: "clock").tag("")
            } else if !translation.languages.contains(where: { $0.minimalIdentifier == translation.targetID }) {
                languageLabel(translation.targetID).tag(translation.targetID)
            }
            languageChoices
        } label: {
            Label("To", systemImage: "translate")
        }
        .crestMenuActionLabelStyle()
        .disabled(translation.isWorking)
    }

    private func languageLabel(_ identifier: String) -> some View {
        Label {
            Text(translation.languageName(identifier))
        } icon: {
            BrowserTranslationLanguageIcon(identifier: identifier)
        }
        .accessibilityLabel(translation.languageName(identifier))
    }

    @ViewBuilder private var languageChoices: some View {
        if !translation.downloadedLanguages.isEmpty {
            Section("Downloaded") {
                ForEach(translation.downloadedLanguages, id: \.minimalIdentifier) { language in
                    languageLabel(language.minimalIdentifier).tag(language.minimalIdentifier)
                }
            }
        }
        if !translation.otherLanguages.isEmpty {
            Section(
                translation.downloadedLanguages.isEmpty
                    ? String(localized: "Languages") : String(localized: "More Languages")
            ) {
                ForEach(translation.otherLanguages, id: \.minimalIdentifier) { language in
                    languageLabel(language.minimalIdentifier).tag(language.minimalIdentifier)
                }
            }
        }
    }
}

struct BrowserTranslationToolbar: View {
    let translation: BrowserPageTranslation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0

    private var usesCompactControls: Bool {
        availableWidth < 560 || dynamicTypeSize.isAccessibilitySize
    }

    private var showsInlineStatus: Bool {
        availableWidth >= 900 && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        BrowserPageToolbarSurface(label: "Page Translation", identifier: "page-translation-toolbar") {
            VStack(alignment: .leading, spacing: 5) {
                toolbarRow(inlineStatus: showsInlineStatus)
                if !showsInlineStatus {
                    translationStatus
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .font(.callout.weight(.medium))
        } background: {
            CrestSurfaceLayer(shape: Rectangle())
        }
        // Read only the externally proposed width. Nested ViewThatFits probes
        // repeatedly measured menus during floating-sidebar transitions and
        // exhausted the iOS scene-update watchdog. Each width now has one tree.
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            availableWidth = $0
        }
    }

    private func toolbarRow(inlineStatus: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "translate")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(translation.isTranslated ? Color.accentColor : .primary)
                .frame(width: controlHeight, height: controlHeight)
                .accessibilityHidden(true)
            toolbarDivider
            if usesCompactControls {
                Menu {
                    BrowserTranslationLanguagePickers(translation: translation)
                        .crestMenuActionLabelStyle()
                } label: {
                    Image(systemName: "globe")
                        .frame(width: controlHeight, height: controlHeight)
                }
                .buttonStyle(BrowserTranslationToolbarControlStyle(isGrouped: true))
                .accessibilityLabel("Languages")
                .help("Languages")
            } else {
                HStack(spacing: 4) {
                    languageMenu(isSource: true)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    languageMenu(isSource: false)
                }
            }
            if inlineStatus && !translation.status.isEmpty {
                toolbarDivider
                translationStatus
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            primaryAction
            toolbarDivider
            Menu {
                BrowserTranslationActions(translation: translation)
                    .crestMenuActionLabelStyle()
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: controlHeight, height: controlHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(BrowserTranslationToolbarControlStyle())
            .help("Translation Options")
            .accessibilityLabel("Translation Options")
            Button(action: translation.dismiss) {
                Image(systemName: "xmark")
                    .frame(width: controlHeight, height: controlHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(BrowserTranslationToolbarControlStyle())
            .help("Dismiss Translation Bar")
            .accessibilityLabel("Dismiss Translation Bar")
            .accessibilityIdentifier("dismiss-translation-bar")
        }
        #if os(macOS)
            .menuStyle(.button)
            .menuIndicator(.hidden)
        #endif
    }

    private func languageMenu(isSource: Bool) -> some View {
        let name = isSource ? translation.languageName(translation.sourceID) : translation.targetName
        return Menu {
            if isSource {
                BrowserTranslationLanguagePickers(translation: translation).sourcePicker
                    .pickerStyle(.inline)
            } else {
                BrowserTranslationLanguagePickers(translation: translation).targetPicker
                    .pickerStyle(.inline)
            }
        } label: {
            HStack(spacing: 6) {
                BrowserTranslationLanguageIcon(identifier: isSource ? translation.sourceID : translation.targetID)
                    .accessibilityHidden(true)
                Text(name).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: controlHeight)
            .contentShape(.rect)
        }
        .buttonStyle(BrowserTranslationToolbarControlStyle(isGrouped: true))
        .disabled(translation.isWorking)
        .accessibilityLabel(isSource ? Text("From") : Text("To"))
        .accessibilityValue(name)
        .help(isSource ? Text("Translate From") : Text("Translate To"))
    }

    private var primaryAction: some View {
        Button {
            if translation.isWorking {
                translation.cancel()
            } else if translation.hasSelectedTranslation {
                translation.showOriginal()
            } else {
                translation.start()
            }
        } label: {
            Group {
                if usesCompactControls {
                    Image(systemName: actionSymbol)
                } else {
                    Label(actionTitle, systemImage: actionSymbol).fixedSize()
                }
            }
            .padding(.horizontal, usesCompactControls ? 0 : 9)
            .frame(minWidth: controlHeight, minHeight: controlHeight)
            .contentShape(.rect)
        }
        .buttonStyle(
            BrowserTranslationToolbarControlStyle(
                isGrouped: true,
                isProminent: !translation.isWorking && !translation.hasSelectedTranslation
            )
        )
        .disabled(!translation.isWorking && !translation.hasSelectedTranslation && !translation.canTranslate)
        .accessibilityLabel(actionTitle)
        .help(actionTitle)
    }

    private var actionTitle: String {
        if translation.isWorking { return String(localized: "Cancel Translation") }
        return translation.hasSelectedTranslation ? String(localized: "Show Original") : String(localized: "Translate")
    }

    private var actionSymbol: String {
        if translation.isWorking { return "stop.fill" }
        return translation.hasSelectedTranslation ? "arrow.uturn.backward" : "translate"
    }

    @ViewBuilder private var translationStatus: some View {
        if !translation.status.isEmpty {
            HStack(spacing: 6) {
                if translation.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: translation.isTranslated ? "checkmark.circle.fill" : "info.circle")
                        .accessibilityHidden(true)
                }
                Text(translation.status)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 22).padding(.horizontal, 2).accessibilityHidden(true)
    }

    private var controlHeight: CGFloat {
        #if os(macOS)
            28
        #else
            44
        #endif
    }
}

private struct BrowserTranslationToolbarControlStyle: ButtonStyle {
    var isGrouped = false
    var isProminent = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isProminent ? Color.accentColor : .primary)
            .background(
                (isProminent ? Color.accentColor : Color.primary)
                    .opacity(configuration.isPressed ? 0.18 : isHovered ? 0.12 : isGrouped ? 0.07 : 0),
                in: .rect(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                if contrast == .increased && isGrouped {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.3), lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : CrestMotion.developerPress, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

/// Native menus need an original-color image to retain an emoji in their icon column.
@MainActor
private struct BrowserTranslationLanguageIcon: View {
    let identifier: String
    @Environment(\.displayScale) private var displayScale
    private static var images: [String: Image] = [:]

    var body: some View {
        if identifier.isEmpty {
            Image(systemName: "text.magnifyingglass")
        } else if let image = localeImage {
            image.renderingMode(.original)
        } else {
            Image(systemName: "character.bubble")
        }
    }

    private var localeImage: Image? {
        let language = Locale.Language(identifier: identifier)
        // Honor an explicit locale first; use Foundation's likely region for
        // region-neutral language identifiers supplied by Translation.
        guard
            let region =
                (Locale(identifier: identifier).region
                ?? Locale(identifier: language.maximalIdentifier).region)?.identifier,
            region.unicodeScalars.count == 2,
            region.unicodeScalars.allSatisfy({ (65...90).contains($0.value) })
        else { return nil }
        let cacheKey = "\(region)|\(displayScale)"
        if let image = Self.images[cacheKey] { return image }
        let flag = String(
            String.UnicodeScalarView(
                region.unicodeScalars.compactMap {
                    UnicodeScalar(127397 + $0.value)
                }))
        let renderer = ImageRenderer(content: Text(flag).font(.system(size: 16)).frame(width: 20, height: 20))
        renderer.scale = displayScale
        guard let cgImage = renderer.cgImage else { return nil }
        let image = Image(decorative: cgImage, scale: displayScale)
        Self.images[cacheKey] = image
        return image
    }
}
