import Foundation

enum BrowserNavigationResponseIntent: Equatable {
    case display
    case download

    static func classify(
        canShowMIMEType: Bool,
        response: URLResponse?
    ) -> BrowserNavigationResponseIntent {
        if !canShowMIMEType || requestsDownload(response) {
            return .download
        }
        return .display
    }

    private static func requestsDownload(_ response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse,
            let disposition = response.value(
                forHTTPHeaderField: "Content-Disposition"
            )
        else {
            return false
        }
        let directive =
            disposition
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return directive == "attachment"
    }
}

struct BrowserDirectMediaNavigation: Equatable {
    enum Kind: String, Equatable {
        case audio
        case video
    }

    let url: URL
    let kind: Kind
    let mimeType: String

    var request: URLRequest {
        URLRequest(url: url)
    }

    var responseHTML: String {
        let source = Self.escapeHTML(url.absoluteString)
        let reportedType = Self.escapeHTML(mimeType)
        let titleSource = url.lastPathComponent.removingPercentEncoding
        let title = Self.escapeHTML(
            titleSource.flatMap { $0.isEmpty ? nil : $0 } ?? "Media"
        )
        let element = kind.rawValue
        return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
              <meta name="color-scheme" content="dark">
              <title>\(title)</title>
              <style>
                :root { color-scheme: dark; font-family: system-ui, sans-serif; }
                * { box-sizing: border-box; }
                html, body { width: 100%; height: 100%; margin: 0; background: #000; }
                body { display: grid; place-items: center; color: #fff; }
                \(element) { display: block; width: 100%; height: 100%; object-fit: contain; }
                audio { height: 4rem; max-width: 44rem; }
                [hidden] { display: none !important; }
                #failure { max-width: 34rem; padding: 2rem; text-align: center; }
                #failure h1 { margin: 0 0 .75rem; font-size: 1.35rem; }
                #failure p { margin: 0 0 1.25rem; color: #c7c7cc; line-height: 1.45; }
                #failure a { color: #6eb4ff; }
              </style>
            </head>
            <body>
              <\(element) controls autoplay playsinline preload="metadata" aria-label="Media player">
                <source src="\(source)" type="\(reportedType)">
              </\(element)>
              <section id="failure" role="alert" hidden>
                <h1>This media file couldn’t be played.</h1>
                <p>The server reported <strong>\(reportedType)</strong>, but WebKit couldn’t decode the file. You can try downloading it instead.</p>
                <a href="\(source)" download>Download media</a>
              </section>
              <script>
                const media = document.querySelector("\(element)");
                media.addEventListener("error", () => {
                  media.hidden = true;
                  document.querySelector("#failure").hidden = false;
                }, { once: true });
              </script>
            </body>
            </html>
            """
    }

    static func classify(
        canShowMIMEType: Bool,
        isForMainFrame: Bool,
        response: URLResponse?
    ) -> BrowserDirectMediaNavigation? {
        guard canShowMIMEType,
            isForMainFrame,
            BrowserNavigationResponseIntent.classify(
                canShowMIMEType: canShowMIMEType,
                response: response
            ) == .display,
            let url = response?.url,
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let mimeType = response?.mimeType?.lowercased()
        else {
            return nil
        }

        let kind: Kind
        if mimeType.hasPrefix("video/") {
            kind = .video
        } else if mimeType.hasPrefix("audio/") {
            kind = .audio
        } else {
            return nil
        }
        return BrowserDirectMediaNavigation(
            url: url,
            kind: kind,
            mimeType: mimeType
        )
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

enum BrowserPopupTrigger: Equatable {
    case explicitUserNavigation
    case scripted
}
