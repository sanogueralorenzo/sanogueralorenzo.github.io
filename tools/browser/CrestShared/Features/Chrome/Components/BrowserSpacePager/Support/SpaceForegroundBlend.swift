import SwiftUI

extension EnvironmentValues {
    @Entry var spaceChromeAccent: Color? = nil
    @Entry var spaceChromeForeground: Color? = nil
}

/// Fixed chrome follows visible Space progress without observing it in tab rows.
struct SpaceForegroundBlend: ViewModifier {
    let ids: [UUID]
    let brandings: [SpaceBranding]
    let accents: [Color]
    let selectedSpaceID: UUID?

    @Environment(\.spacePagerPresentation) private var presentation
    @Environment(\.colorScheme) private var colorScheme
    @State private var foreground = SpaceForegroundPresentation()

    /// Each Space's text tone over the window's appearance.
    private var tones: [SpaceForegroundPresentation.Tone] {
        zip(ids, brandings).map { id, branding in
            SpaceForegroundPresentation.Tone(
                id: id, white: branding.shown.foregroundTone(over: colorScheme) == .light ? 1 : 0)
        }
    }

    init(spaces: [SpaceModel], selectedSpaceID: UUID?) {
        ids = spaces.map(\.id)
        brandings = spaces.map(\.settings.look)
        accents = brandings.map { $0.primaryColor.color }
        self.selectedSpaceID = selectedSpaceID
    }

    func body(content: Content) -> some View {
        content
            .modifier(
                SpaceForegroundTone(
                    position: foreground.position ?? CGFloat(tones.firstIndex { $0.id == selectedSpaceID } ?? 0),
                    tones: tones, accents: accents)
            )
            .onAppear { foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID) }
            .onChange(of: tones) { _, _ in
                foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID)
            }
            .onChange(of: selectedSpaceID) { _, _ in
                foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID)
            }
            .onChange(of: presentation.map(ObjectIdentifier.init)) { _, _ in
                foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID)
            }
            .onDisappear { foreground.disconnect() }
    }
}

private struct SpaceForegroundTone: ViewModifier, Animatable {
    nonisolated var position: CGFloat
    let tones: [SpaceForegroundPresentation.Tone]
    let accents: [Color]

    nonisolated var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func body(content: Content) -> some View {
        let foreground = Color(white: SpaceForegroundPresentation.white(at: position, tones: tones))
        content
            .foregroundStyle(foreground)
            .environment(\.spaceChromeForeground, foreground)
            .environment(\.spaceChromeAccent, accent)
    }

    private var accent: Color? {
        guard let sample = SpacePagerInterpolation(position: position, count: accents.count) else { return nil }
        return accents[sample.lower].mix(with: accents[sample.upper], by: Double(sample.fraction), in: .device)
    }
}
