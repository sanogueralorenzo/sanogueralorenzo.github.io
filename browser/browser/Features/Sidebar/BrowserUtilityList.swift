import SwiftUI

struct BrowserUtilityList: View {
    let utility: BrowserUtility
    let store: BrowserStore
    @State private var search = ""
    @State private var showsRecentlyClosed = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    store.utility = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BrowserChromeButtonStyle())
                .accessibilityLabel("Back to Tabs")
                Text(utility.rawValue).font(.headline)
                Spacer()
                if utility == .history && !showsRecentlyClosed && search.isEmpty {
                    Button("Clear…") { store.presentClearBrowsingData(in: store.activeSpace.id) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear Browsing Data")
                }
            }
            if utility == .history {
                Picker("History view", selection: $showsRecentlyClosed) {
                    Text("Visited").tag(false)
                    Text("Recently Closed").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            TextField("Search " + searchScope, text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 4) {
                    switch utility {
                    case .history:
                        if showsRecentlyClosed {
                            recentlyClosedEntries
                        } else {
                            visitedEntries
                        }
                    case .downloads:
                        let downloads = store.session.downloads.filter {
                            $0.spaceID == store.activeSpace.id && matches($0.name)
                        }
                        if downloads.isEmpty { empty("No downloads", "No matching downloads") }
                        ForEach(downloads) { download in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(download.name).lineLimit(1)
                                if download.status == .running && download.expected > 0 {
                                    ProgressView(value: Double(download.received), total: Double(download.expected))
                                }
                                Text(
                                    download.error
                                        ?? (download.status == .choosing
                                            ? "Starting" : download.status.rawValue.capitalized)
                                ).font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    if download.status == .choosing {
                                        Button("Cancel") { store.cancelDownload(download.id) }
                                    } else if download.status == .running {
                                        Button("Pause") {
                                            if let job = store.activeDownloads.first(where: { $0.id == download.id }) {
                                                Task { await job.pause() }
                                            }
                                        }
                                        Button("Cancel") {
                                            store.cancelDownload(download.id)
                                        }
                                    } else if download.resumeData != nil {
                                        Button("Resume") { store.resumeDownload(download) }
                                    } else if download.status == .completed {
                                        Button("Open") { store.openDownload(download) }
                                        Button("Show in Finder") { store.revealDownload(download) }
                                    } else if download.requestMethod == "GET", download.source != nil {
                                        Button("Restart") { store.restartDownload(download) }
                                    } else if let source = download.source {
                                        Button("Open Source Page") { store.open(source) }
                                    }
                                }.buttonStyle(.borderless)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 6)
    }

    private var searchScope: String {
        utility == .history && showsRecentlyClosed ? "Recently Closed" : utility.rawValue
    }

    @ViewBuilder private var visitedEntries: some View {
        let entries = store.session.history.filter {
            $0.spaceID == store.activeSpace.id && matches($0.title + " " + $0.url.absoluteString)
        }
        if entries.isEmpty { empty("No visited pages", "No matching pages") }
        ForEach(entries) { visit in
            Button {
                store.open(visit.url)
            } label: {
                entry(title: visit.title, subtitle: visit.url.host ?? visit.url.absoluteString, symbol: "globe")
            }
            .buttonStyle(BrowserChromeButtonStyle(controlSize: nil, cornerRadius: 16))
        }
    }

    @ViewBuilder private var recentlyClosedEntries: some View {
        let entries = store.session.archive.filter { item in
            item.spaceID == store.activeSpace.id
                && (matches(item.tab.title) || item.tab.customTitle.map(matches) == true
                    || matches(item.tab.url?.absoluteString ?? ""))
        }
        if entries.isEmpty {
            empty("No recently closed tabs", "No matching tabs")
        } else {
            ForEach(entries) { item in
                Button {
                    store.restore(item)
                } label: {
                    entry(
                        title: item.tab.customTitle ?? item.tab.title, subtitle: item.tab.url?.host ?? "",
                        symbol: "arrow.uturn.backward")
                }
                .buttonStyle(BrowserChromeButtonStyle(controlSize: nil, cornerRadius: 16))
            }
        }
    }

    private func empty(_ label: String, _ noMatches: String) -> some View {
        Text(search.isEmpty ? label : noMatches)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func matches(_ text: String) -> Bool { search.isEmpty || text.localizedCaseInsensitiveContains(search) }

    private func entry(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension BrowserStore {
    func presentUtility(_ utility: BrowserUtility) {
        self.utility = utility
        sidebarRevealed = true
    }
}
