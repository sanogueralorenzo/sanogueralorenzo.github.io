import SwiftUI
import WebKit

struct BrowserPageContent: View {
    let page: BrowserPage
    let store: BrowserStore
    var body: some View {
        ZStack(alignment: .topTrailing) {
            BrowserWebView(
                page: page, store: store, ownerWindowID: page.hostingWindowID, revision: store.runtimeRevision,
                mirrorImage: page.mirrorImage
            ).id(page.id)
            if page.loading.showsBackground {
                BrowserBrandTheme.canvas.allowsHitTesting(false).accessibilityHidden(true)
                if page.waitsForContentBlocking {
                    BrowserContentBlockingProgress()
                }
            }
            if let failure = page.failure {
                VStack(spacing: 14) {
                    Text(failure).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Reload") {
                        page.applyContentBlocking()
                        page.reloadAfterContentBlocking()
                    }.buttonStyle(.bordered)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(BrowserBrandTheme.canvas)
            }
            BrowserPageLoadingBar(indicator: page.loading.indicator).id(page.id)
            if store.findsPage && store.selectedTab?.id == page.id {
                BrowserFindBar(page: page, store: store).padding(12)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).modifier(PageTranslation(page: page, store: store))
    }
}

private struct BrowserContentBlockingProgress: View {
    @State private var visible = false

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(BrowserContentBlocking.preparingLabel).font(.callout)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(visible ? 1 : 0)
        .accessibilityHidden(!visible)
        .allowsHitTesting(false)
        .task {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }
            visible = true
        }
    }
}

private struct BrowserFindBar: View {
    let page: BrowserPage
    let store: BrowserStore
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            TextField("Find in Page", text: Binding(get: { store.findText }, set: { store.findText = $0 }))
                .textFieldStyle(.plain).frame(width: 200).focused($focused).onSubmit { find(false) }
            Button {
                find(true)
            } label: {
                Image(systemName: "chevron.up")
            }
            Button {
                find(false)
            } label: {
                Image(systemName: "chevron.down")
            }
            Button {
                store.findsPage = false
            } label: {
                Image(systemName: "xmark")
            }
        }.padding(10).background(BrowserBrandTheme.surface, in: RoundedRectangle(cornerRadius: BrowserRadius.control))
            .buttonStyle(BrowserChromeButtonStyle()).onChange(of: store.findText) { find(false) }.onAppear {
                focused = true
            }.onExitCommand { store.findsPage = false }
    }
    private func find(_ backwards: Bool) {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        page.webView.find(store.findText, configuration: configuration) { _ in }
    }
}
