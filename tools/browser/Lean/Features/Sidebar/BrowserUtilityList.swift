import SwiftUI

struct BrowserUtilityList: View {
    let utility: BrowserUtility
    let store: BrowserStore
    @State private var search = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    store.utility = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(LeanChromeButtonStyle())
                Text(utility.rawValue).font(.headline)
                Spacer()
                if utility == .history {
                    Button("Clear") { store.clearHistory() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            TextField("Search " + utility.rawValue, text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 4) {
                    switch utility {
                    case .history:
                        ForEach(
                            store.session.history.filter {
                                $0.spaceID == store.activeSpace.id && matches($0.title + $0.url.absoluteString)
                            }
                        ) { visit in
                            Button {
                                store.open(visit.url)
                            } label: {
                                entry(
                                    title: visit.title, subtitle: visit.url.host ?? visit.url.absoluteString,
                                    symbol: "globe")
                            }
                            .buttonStyle(LeanChromeButtonStyle(controlSize: nil, cornerRadius: 16))
                        }
                    case .archive:
                        ForEach(
                            store.session.archive.filter { $0.spaceID == store.activeSpace.id && matches($0.tab.title) }
                        ) { item in
                            Button {
                                store.restore(item)
                            } label: {
                                entry(
                                    title: item.tab.customTitle ?? item.tab.title, subtitle: item.tab.url?.host ?? "",
                                    symbol: "arrow.uturn.backward")
                            }
                            .buttonStyle(LeanChromeButtonStyle(controlSize: nil, cornerRadius: 16))
                        }
                    case .downloads:
                        ForEach(
                            store.session.downloads.filter { $0.spaceID == store.activeSpace.id && matches($0.name) }
                        ) { download in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(download.name).lineLimit(1)
                                if download.status == .running && download.expected > 0 {
                                    ProgressView(value: Double(download.received), total: Double(download.expected))
                                }
                                Text(download.error ?? download.status.rawValue.capitalized).font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    if download.status == .running {
                                        Button("Pause") {
                                            if let job = store.activeDownloads.first(where: { $0.id == download.id }) {
                                                Task { await job.pause() }
                                            }
                                        }
                                        Button("Cancel") {
                                            store.activeDownloads.first(where: { $0.id == download.id })?.cancel()
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
