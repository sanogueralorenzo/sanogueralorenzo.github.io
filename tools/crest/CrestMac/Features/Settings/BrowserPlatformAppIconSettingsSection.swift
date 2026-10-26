import SwiftUI

struct BrowserPlatformAppIconSettingsSection: View {
    @AppStorage(BrowserMacAppIconAssets.preferenceKey, store: BrowserMacDockTile.shared.defaults)
    private var selectedName = ""
    @State private var showsError = false
    @State private var appearanceRevision = 0
    @State private var appearanceObserver: BrowserMacAppIconAppearanceObserver?

    var body: some View {
        CrestSettingsGroup(
            "App icon",
            settings: [resettable]
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 12)], spacing: 16) {
                iconChoice(name: "", title: "Crest", preview: "CrestPreview")
                ForEach(SpaceHouse.all, id: \.self) { house in
                    iconChoice(name: house.appIconName, title: house.title, preview: house.appIconName + "Preview")
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            appearanceObserver = BrowserMacAppIconAppearanceObserver { appearanceRevision += 1 }
        }
        .onDisappear {
            appearanceObserver?.stop()
            appearanceObserver = nil
        }
        .alert("Couldn’t change app icon", isPresented: $showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Crest could not load this icon. Please try again.")
        }
    }

    private var resettable: CrestResettableSetting {
        CrestResettableSetting(title: "App icon", isDefault: selectedName.isEmpty) {
            showsError = !BrowserMacDockTile.shared.select("")
        }
    }

    private func iconChoice(name: String, title: LocalizedStringResource, preview: String) -> some View {
        Button {
            showsError = !BrowserMacDockTile.shared.select(name)
        } label: {
            VStack(spacing: 6) {
                Image(
                    nsImage: name.isEmpty
                        ? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
                        : BrowserMacAppIconAssets.image(named: name, in: .main) ?? NSImage()
                )
                .resizable().scaledToFit()
                .id(appearanceRevision)
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(selectedName == name ? Color.accentColor : .clear, lineWidth: 3)
                }
                Text(title).font(.caption).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedName == name ? .isSelected : [])
        .accessibilityIdentifier("app-icon-" + (name.isEmpty ? "default" : name))
    }
}
