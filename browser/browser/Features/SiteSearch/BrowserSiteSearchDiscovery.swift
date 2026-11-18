import WebKit

@MainActor
final class BrowserSiteSearchDiscovery {
    private struct SearchForm {
        let action: URL
        let field: String
    }

    private var inspectedURL: URL?
    private var forms: [SearchForm] = []
    private var submission: (url: URL, search: BrowserSiteSearch)?
    private var successfulURL: URL?

    func requested(_ action: WKNavigationAction, url: URL) {
        successfulURL = nil
        submission = nil
        guard action.navigationType == .formSubmitted, action.sourceFrame.isMainFrame,
            action.request.httpMethod == "GET", !action.shouldPerformDownload,
            let inspectedURL, BrowserURLs.same(action.sourceFrame.request.url, inspectedURL)
        else { return }
        for form in forms {
            if let search = BrowserSiteSearch.fromForm(action: form.action, field: form.field, submittedURL: url) {
                submission = (url, search)
                return
            }
        }
    }

    func received(_ response: WKNavigationResponse) {
        guard response.isForMainFrame else { return }
        successfulURL = nil
        if let http = response.response as? HTTPURLResponse, (200...299).contains(http.statusCode),
            response.canShowMIMEType, http.mimeType == "text/html" || http.mimeType == "application/xhtml+xml"
        {
            successfulURL = http.url
        }
    }

    func finished(_ page: BrowserPage) {
        let submission = self.submission
        self.submission = nil
        inspectedURL = nil
        forms = []
        guard !page.isRetired, let url = page.webView.url, let origin = BrowserSiteSearch.origin(of: url),
            successfulURL.flatMap(BrowserSiteSearch.origin(of:)) == origin,
            let store = page.owner, store.siteSearch(for: url, in: page.spaceID) == nil
        else { return }
        if let submission, BrowserURLs.same(submission.url, url), BrowserURLs.same(submission.url, successfulURL) {
            store.rememberSiteSearch(submission.search, from: url, in: page.spaceID)
            return
        }

        let revision = page.documentRevision
        page.webView.callAsyncJavaScript(Self.inspectScript, arguments: [:], in: nil, in: .defaultClient) {
            [weak self, weak page] result in
            guard let self, let page, !page.isRetired, page.documentRevision == revision,
                let currentURL = page.webView.url, BrowserSiteSearch.origin(of: currentURL) == origin,
                case .success(let value) = result,
                let details = value as? [String: Any]
            else { return }
            inspectedURL = currentURL
            forms = (details["forms"] as? [[String: String]] ?? []).compactMap { entry in
                guard let address = entry["action"], let action = URL(string: address),
                    BrowserSiteSearch.origin(of: action) == origin, let field = entry["field"],
                    !field.isEmpty, field.utf8.count <= 256
                else { return nil }
                return SearchForm(action: action, field: field)
            }
            guard let advertised = details["descriptor"] as? String, let descriptor = URL(string: advertised),
                BrowserSiteSearch.origin(of: descriptor) == origin
            else { return }
            Task { [weak page] in
                guard let search = try? await BrowserSearchClient.shared.siteSearch(from: descriptor, origin: origin),
                    let page, !page.isRetired, page.documentRevision == revision
                else { return }
                page.owner?.rememberSiteSearch(search, from: url, in: page.spaceID)
            }
        }
    }

    private static let inspectScript = #"""
        const descriptor = [...document.querySelectorAll('link[rel~="search"][type="application/opensearchdescription+xml"]')]
            .find(link => URL.canParse(link.href, location.href)
                && new URL(link.href, location.href).origin === location.origin)?.href ?? "";
        const forms = [];
        for (const form of document.forms) {
            if (forms.length === 16) break;
            if (form.method !== "get" || form.hasAttribute("onsubmit") || !["", "_self"].includes(form.target)) continue;
            if (!URL.canParse(form.action || location.href)) continue;
            const action = new URL(form.action || location.href);
            if (action.origin !== location.origin) continue;
            const fields = [...form.elements].filter(field => field.name && !field.matches(":disabled"));
            const input = fields.find(field => field instanceof HTMLInputElement
                && (field.type === "search" || field.type === "text"
                    && (form.getAttribute("role") === "search" || form.closest("search"))));
            if (!input || fields.some(field => field !== input && !["submit", "button", "reset"].includes(field.type))) continue;
            forms.push({ action: action.href, field: input.name });
        }
        return {descriptor, forms};
        """#
}

extension BrowserStore {
    func siteSearch(for url: URL, in spaceID: UUID) -> BrowserSiteSearch? {
        guard let origin = BrowserSiteSearch.origin(of: url) else { return nil }
        return session.spaces.first(where: { $0.id == spaceID })?.siteSearches?.first { $0.origin == origin }
    }

    func rememberSiteSearch(_ search: BrowserSiteSearch, from url: URL, in spaceID: UUID) {
        guard let index = session.spaces.firstIndex(where: { $0.id == spaceID }),
            session.spaces[index].isPrivate || session.history.contains(where: { $0.spaceID == spaceID && $0.url == url })
        else { return }
        var entries = session.spaces[index].siteSearches ?? []
        guard entries.first(where: { $0.origin == search.origin }) != search else { return }
        entries.removeAll { $0.origin == search.origin }
        entries.insert(search, at: 0)
        session.spaces[index].siteSearches = Array(entries.prefix(BrowserSiteSearch.maximumCount))
        changed()
    }
}
