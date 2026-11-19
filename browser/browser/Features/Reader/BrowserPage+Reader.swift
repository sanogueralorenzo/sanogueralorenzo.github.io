import WebKit

extension BrowserPage {
    func refreshReaderAvailability() async {
        readerAvailable =
            (try? await webView.callAsyncJavaScript(
                BrowserReaderModeJavaScriptBridge.source,
                arguments: ["action": "availability"], in: nil, contentWorld: .defaultClient) as? Bool) ?? false
    }

    func toggleReader() {
        let action = isReaderMode ? "deactivate" : "activate"
        Task {
            if (try? await webView.callAsyncJavaScript(
                BrowserReaderModeJavaScriptBridge.source,
                arguments: ["action": action, "readerModeLabel": "Reader Mode"], in: nil, contentWorld: .defaultClient)
                as? Bool) == true
            {
                isReaderMode.toggle()
            }
        }
    }
}
