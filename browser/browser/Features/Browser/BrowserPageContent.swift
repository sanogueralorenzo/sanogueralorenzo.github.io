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
                BrowserFindBar(page: page, store: store).padding(.top, 8)
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
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    field.frame(width: 200)
                    controls
                }
                VStack(alignment: .leading, spacing: 4) {
                    field.frame(maxWidth: 200)
                    controls
                }
            }
            if store.findMatch == false {
                Text("No matches").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 6)
        .background(BrowserBrandTheme.surface, in: RoundedRectangle(cornerRadius: BrowserRadius.control))
        .buttonStyle(BrowserChromeButtonStyle())
        .onChange(of: store.findText) { _, _ in store.findInPage() }
        .onChange(of: page.documentRevision) { _, _ in store.findMatch = nil }
        .onAppear { focused = true }
        .onExitCommand { store.findsPage = false }
    }

    private var field: some View {
        TextField("Find in Page", text: Binding(get: { store.findText }, set: { store.findText = $0 }))
            .textFieldStyle(.plain).focused($focused).onSubmit { store.findInPage() }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button { store.findInPage(backwards: true) } label: { Image(systemName: "chevron.up") }
                .accessibilityLabel("Previous Match")
            Button { store.findInPage() } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Next Match")
            Button { store.findsPage = false } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Close Find")
        }
    }
}
