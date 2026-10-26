import SwiftUI

/// A labelled row with a distinct native control on its trailing edge.
struct CrestFormControlRow<Control: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String
    var tint: Color = CrestBrandTheme.accent
    @ViewBuilder let control: () -> Control

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String,
        tint: Color = CrestBrandTheme.accent,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.control = control
    }

    var body: some View {
        HStack(spacing: CrestFormRowMetrics.contentSpacing) {
            CrestFormRowLabel(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint
            )
            Spacer(minLength: CrestSpacing.small)
            control()
        }
        .frame(minHeight: CrestFormRowMetrics.minimumHeight)
    }
}

#if DEBUG
    #Preview("Component") {
        @Previewable @State var enabled = true
        Form {
            CrestFormControlRow(
                "Content Blocking", subtitle: "Block known trackers", systemImage: "shield.lefthalf.filled"
            ) {
                Toggle("Content Blocking", isOn: $enabled).labelsHidden()
            }
        }.crestSettingsForm().frame(width: 420, height: 180)
    }
#endif
