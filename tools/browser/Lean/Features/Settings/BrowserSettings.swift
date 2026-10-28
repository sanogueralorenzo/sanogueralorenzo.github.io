import SwiftUI
import WebKit

enum BrowserSettingsSelection: Hashable {
    case general, engines, sync, privacy
    case space(UUID)
    case agents, advanced, about

    var title: String {
        switch self {
        case .general: "General"
        case .engines: "Engines"
        case .sync: "Sync"
        case .privacy: "Privacy & Permissions"
        case .space: "Spaces"
        case .agents: "Agents"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .engines: "cpu"
        case .sync: "arrow.triangle.2.circlepath.icloud"
        case .privacy: "hand.raised"
        case .space: "capsule.fill"
        case .agents: "sparkles"
        case .advanced: "switch.2"
        case .about: "info.circle"
        }
    }
}

struct BrowserSettings: View {
    let store: BrowserStore
    private var query: String {
        get { store.settingsState.query }
        nonmutating set { store.settingsState.query = newValue }
    }
    @State private var showsSpaceEditor = false
    @State private var arrangingSpaces = false

    private var selection: Binding<BrowserSettingsSelection?> {
        Binding(get: { store.settingsSelection }, set: { if let value = $0 { store.settingsSelection = value } })
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 224)
            Divider()
            VStack(spacing: 0) {
                Text(pageTitle).font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).frame(height: 52)
                Divider()
                page
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .controlSize(.regular)
        .background(LeanBrandTheme.canvas)
        .sheet(isPresented: $showsSpaceEditor) {
            SpaceEditor(space: nil, store: store) { showsSpaceEditor = false }
        }
    }

    private var pageTitle: String {
        if case .space(let id) = store.settingsSelection {
            return store.session.spaces.first { $0.id == id }?.name ?? "Spaces"
        }
        return store.settingsSelection.title
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lean").font(.system(size: 14, weight: .semibold))
                    Text(
                        "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (1)"
                    )
                    Text(
                        "WebKit \((Bundle(for: WKWebView.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "").split(separator: ".").first.map(String.init) ?? "")"
                    )
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.accessibilityElement(children: .combine).padding(.horizontal, 14).padding(.top, 14)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search settings", text: Binding(get: { query }, set: { query = $0 })).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
            List(selection: selection) {
                Section {
                    destination(.general)
                    destination(.engines)
                    destination(.sync)
                    destination(.privacy)
                }
                Section {
                    ForEach(store.session.spaces.filter { matches($0.name + " identity privacy downloads") }) { space in
                        Label {
                            Text(space.name).lineLimit(1)
                        } icon: {
                            BrowserSpacePill(color: space.color).frame(height: 18)
                        }
                        .tag(BrowserSettingsSelection.space(space.id))
                        .contextMenu {
                            Button("Open Space") { store.selectSpace(space.id) }
                            Button("Delete Space", role: .destructive) { store.deleteSpace(space.id) }
                                .disabled(!space.isPrivate && store.session.spaces.filter { !$0.isPrivate }.count == 1)
                        }
                        .moveDisabled(!arrangingSpaces)
                    }
                    .onMove { source, destination in
                        store.session.spaces.move(fromOffsets: source, toOffset: destination)
                        store.changed()
                    }
                } header: {
                    HStack {
                        Text("Spaces")
                        Spacer()
                        Button {
                            arrangingSpaces.toggle()
                        } label: {
                            Image(systemName: arrangingSpaces ? "checkmark" : "pencil")
                        }
                        .accessibilityLabel(arrangingSpaces ? "Done" : "Rearrange Spaces")
                        .disabled(store.session.spaces.count < 2 && !arrangingSpaces)
                        Button {
                            showsSpaceEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add Space")
                    }.buttonStyle(.borderless).padding(.trailing, 6).accessibilityElement(children: .contain)
                }
                Section {
                    destination(.agents)
                    destination(.advanced)
                    destination(.about)
                }
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden)
        }
        .background(LeanBrandTheme.canvas)
    }

    @ViewBuilder private func destination(_ destination: BrowserSettingsSelection) -> some View {
        if matches(destination.title + searchTerms(destination)) {
            Label(destination == .privacy ? "Privacy" : destination.title, systemImage: destination.symbol)
                .tag(destination).listItemTint(.monochrome)
        }
    }

    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedStandardContains(query) }

    private func searchTerms(_ destination: BrowserSettingsSelection) -> String {
        switch destination {
        case .general: " search provider Google DuckDuckGo Bing Brave zoom default browser translation language"
        case .privacy:
            " permissions camera microphone location notifications passkeys content blocking ads trackers history cookies data retention"
        case .advanced: " import export backup bookmarks"
        case .about: " version build updates license"
        default: ""
        }
    }

    @ViewBuilder private var page: some View {
        switch store.settingsSelection {
        case .general: BrowserGeneralSettings(store: store)
        case .privacy:
            BrowserSystemSettings(store: store) {
                store.settingsSelection = .space($0)
                store.settingsSpacePrivacy = true
            }
        case .space(let id): BrowserSpaceSettings(store: store, spaceID: id)
        case .engines, .sync, .agents, .advanced, .about:
            BrowserAdditionalSettings(store: store, selection: store.settingsSelection)
        }
    }
}

struct BrowserSettingsForm<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form(content: content).formStyle(.grouped).scrollContentBackground(.hidden)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LeanBrandTheme.canvas)
    }
}
