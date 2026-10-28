import SwiftUI

/// One setting: its title on the leading edge, its control on the trailing
/// edge, and the reset it offers once modified.
///
/// Every row aligns the same way — title, then control — so a column of
/// settings reads as a table, and a toggle is always the switch the rest of
/// Crest uses rather than the checkbox a nested control would otherwise become.
///
/// The reset reserves a consistent slot beside the label. Showing or hiding it
/// never moves the control, and its larger hit target stays clear of the text.
struct CrestSettingRow<Control: View>: View {
    private let title: LocalizedStringKey
    private let setting: CrestResettableSetting?
    private let control: Control

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ title: LocalizedStringKey,
        setting: CrestResettableSetting? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.setting = setting
        self.control = control()
    }

    var body: some View {
        LabeledContent {
            control
                .toggleStyle(.switch)
        } label: {
            label
        }
        .modifier(CrestSettingResetContextMenu(setting: setting))
    }

    private var label: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            resetControl
        }
    }

    @ViewBuilder
    private var resetControl: some View {
        if let setting {
            Button(action: setting.reset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(.quaternary, in: .circle)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(showsReset ? 1 : 0)
            // Only the affordance fades. Animating the row would carry the
            // slider's own value changes along with it.
            .animation(
                CrestMotion.surface.unlessReducingMotion(reduceMotion),
                value: showsReset
            )
            .allowsHitTesting(showsReset)
            .accessibilityHidden(!showsReset)
            .accessibilityLabel(Text("Reset \(Text(title)) to default"))
            .help(Text("Reset \(Text(title)) to default"))
        }
    }

    private var showsReset: Bool {
        guard let setting else { return false }
        return !setting.isDefault
    }
}

/// The row's context menu, attached whether or not there is anything in it.
///
/// Attaching it only while the value is modified would change the row's
/// structural identity the moment a drag leaves the default, and SwiftUI would
/// rebuild the slider under the pointer mid-drag — which is how a border width
/// used to jump to the end of its track. The menu is simply empty until there
/// is something to put back.
private struct CrestSettingResetContextMenu: ViewModifier {
    let setting: CrestResettableSetting?

    func body(content: Content) -> some View {
        content.contextMenu {
            if let setting, !setting.isDefault {
                Button("Reset to Default", systemImage: "arrow.counterclockwise", action: setting.reset)
            }
        }
    }
}

#if DEBUG
    #Preview("Toggle and reset") {
        @Previewable @State var enabled = true
        Form {
            CrestSettingRow(
                "Show sidebar", setting: CrestSettingValue($enabled, default: false).resettable("Show sidebar")
            ) {
                Toggle("Show sidebar", isOn: $enabled).labelsHidden()
            }
        }.crestSettingsForm().frame(width: 420, height: 160)
    }
#endif
