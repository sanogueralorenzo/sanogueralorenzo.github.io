import Foundation
import WebKit

// MARK: - Types

struct BrowserFaviconDiscovery: Equatable, Sendable {
    let iconURLs: [URL]
    let manifestURLs: [URL]
    let userAgent: String?
}

@MainActor
enum BrowserFaviconCapture {
    nonisolated static let maximumByteCount = 128 * 1_024

    static func capture(from webView: WKWebView) async -> Data? {
        guard let pageURL = webView.url, isHTTPFamily(pageURL), !Task.isCancelled else { return nil }

        let value = try? await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .defaultClient
        )
        let discovered = discovery(from: value, pageURL: pageURL)
        guard webView.url == pageURL, !Task.isCancelled else { return nil }
        var manifestIcons: [URL] = []
        for manifestURL in discovered.manifestURLs {
            guard
                let manifest = await downloadResource(
                    manifestURL,
                    in: webView,
                    pageURL: pageURL,
                    userAgent: discovered.userAgent,
                    maximumByteCount: 1_024 * 1_024,
                    accept: BrowserFaviconResourceLoader.manifestAccept
                )
            else { continue }
            guard webView.url == pageURL, !Task.isCancelled else { return nil }
            manifestIcons.append(
                contentsOf: manifestIconURLs(
                    from: manifest.data,
                    manifestURL: manifest.url
                )
            )
        }
        let fallbackURL = URL(string: "/favicon.ico", relativeTo: pageURL)?
            .absoluteURL
        let candidates = prioritizedCandidateURLs(
            discoveredIconURLs: discovered.iconURLs,
            manifestIconURLs: manifestIcons,
            fallbackURL: fallbackURL
        )

        var visited: Set<URL> = []
        for candidate in candidates where visited.insert(candidate).inserted {
            guard webView.url == pageURL, !Task.isCancelled else { return nil }
            if let data = decodeDataURL(candidate.absoluteString) {
                if let renderableData = await renderableCandidateData(
                    data,
                    mimeType: dataURLMIMEType(candidate.absoluteString),
                    in: webView
                ) {
                    guard webView.url == pageURL, !Task.isCancelled else { return nil }
                    return renderableData
                }
                continue
            }
            if let downloadedCandidate = await downloadResource(
                candidate,
                in: webView,
                pageURL: pageURL,
                userAgent: discovered.userAgent,
                maximumByteCount: maximumByteCount,
                accept: BrowserFaviconResourceLoader.iconAccept
            ), downloadedCandidate.isImage {
                guard webView.url == pageURL, !Task.isCancelled else { return nil }
                if let renderableData = await renderableCandidateData(
                    downloadedCandidate.data,
                    mimeType: downloadedCandidate.mimeType,
                    in: webView
                ) {
                    guard webView.url == pageURL, !Task.isCancelled else { return nil }
                    return renderableData
                }
            }
        }
        return nil
    }

    static func discovery(from value: Any?, pageURL: URL) -> BrowserFaviconDiscovery {
        guard let result = value as? [String: Any] else {
            return BrowserFaviconDiscovery(
                iconURLs: [],
                manifestURLs: [],
                userAgent: nil
            )
        }
        return BrowserFaviconDiscovery(
            iconURLs: resolvedIconURLs(
                result["icons"],
                relativeTo: pageURL
            ),
            manifestURLs: resolvedURLs(
                result["manifests"],
                relativeTo: pageURL
            ),
            userAgent: normalizedUserAgent(result["userAgent"] as? String)
        )
    }

    static func decodeDataURL(_ value: String) -> Data? {
        guard value.starts(with: "data:image/"),
            let separator = value.firstIndex(of: ",")
        else { return nil }

        let metadata = value[..<separator]
        guard metadata.hasSuffix(";base64") else { return nil }

        let payload = value[value.index(after: separator)...]
        guard payload.utf8.count <= ((maximumByteCount * 4 / 3) + 8),
            let data = Data(base64Encoded: String(payload)),
            !data.isEmpty,
            data.count <= maximumByteCount
        else { return nil }
        return data
    }

    nonisolated static func downloadCandidate(
        _ iconURL: URL,
        userAgent: String? = nil,
        session: URLSession? = nil
    ) async -> Data? {
        guard
            let resource = await BrowserFaviconResourceLoader.download(
                iconURL,
                maximumByteCount: maximumByteCount,
                accept: BrowserFaviconResourceLoader.iconAccept,
                userAgent: userAgent,
                session: session
            ), resource.isImage
        else { return nil }
        return resource.data
    }

    static func rasterizedSVGData(
        _ data: Data,
        in webView: WKWebView,
        maximumPixelSize: Int = 128
    ) async -> Data? {
        guard !data.isEmpty, data.count <= maximumByteCount else { return nil }
        let pixelSize = min(
            max(1, maximumPixelSize),
            maximumRasterizedPixelSize
        )
        guard
            let value = try? await webView.callAsyncJavaScript(
                rasterizeSVGScript,
                arguments: [
                    "svgBase64": data.base64EncodedString(),
                    "maximumPixelSize": pixelSize,
                ],
                in: nil,
                contentWorld: .defaultClient
            ),
            let dataURL = value as? String
        else { return nil }
        return decodeDataURL(dataURL)
    }

    private static func downloadResource(
        _ url: URL,
        in webView: WKWebView,
        pageURL: URL,
        userAgent: String?,
        maximumByteCount: Int,
        accept: String
    ) async -> BrowserFaviconResourceLoader.Resource? {
        guard isHTTPFamily(url), webView.url == pageURL, !Task.isCancelled else { return nil }
        // The isolated world keeps page scripts from replacing fetch. WebKit
        // owns cookie scope, SameSite, Space storage, and redirect credentials.
        // No referrer is needed for discovery, even when a policy permits one.
        let value = try? await webView.callAsyncJavaScript(
            fetchResourceScript,
            arguments: [
                "resourceURL": url.absoluteString,
                "pageURL": pageURL.absoluteString,
                "maximumByteCount": maximumByteCount,
                "accept": accept,
            ],
            in: nil,
            contentWorld: .defaultClient
        )
        guard webView.url == pageURL, !Task.isCancelled else { return nil }
        if let result = value as? [String: Any],
            let base64 = result["base64"] as? String,
            base64.utf8.count <= ((maximumByteCount + 2) / 3) * 4,
            let data = Data(base64Encoded: base64),
            !data.isEmpty, data.count <= maximumByteCount,
            let source = result["url"] as? String, let responseURL = URL(string: source)
        {
            return .init(data: data, mimeType: result["mimeType"] as? String, url: responseURL)
        }
        // Public CDN icons may not grant CORS access. The native fallback
        // carries neither the page URL nor its credentials, on any redirect.
        return await BrowserFaviconResourceLoader.download(
            url,
            maximumByteCount: maximumByteCount,
            accept: accept,
            userAgent: userAgent
        )
    }

    private static func renderableCandidateData(
        _ data: Data,
        mimeType: String?,
        in webView: WKWebView
    ) async -> Data? {
        guard isSVG(data, mimeType: mimeType) else { return data }
        return await rasterizedSVGData(data, in: webView)
    }

    private static func isSVG(_ data: Data, mimeType: String?) -> Bool {
        if mimeType?.lowercased() == "image/svg+xml" { return true }
        guard
            let prefix = String(data: data.prefix(2_048), encoding: .utf8)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines.union(
                        CharacterSet(charactersIn: "\u{feff}")
                    )
                )
                .lowercased()
        else { return false }
        return prefix.hasPrefix("<svg")
            || (prefix.hasPrefix("<?xml") && prefix.contains("<svg"))
    }

    private static func dataURLMIMEType(_ value: String) -> String? {
        guard value.starts(with: "data:"),
            let separator = value.firstIndex(of: ";")
        else { return nil }
        let start = value.index(value.startIndex, offsetBy: 5)
        return String(value[start..<separator]).lowercased()
    }

    static func manifestIconURLs(
        from data: Data,
        manifestURL: URL
    ) -> [URL] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let manifest = object as? [String: Any],
            let icons = manifest["icons"] as? [[String: Any]]
        else { return [] }
        return icons.enumerated().compactMap {
            index,
            icon -> ManifestIconCandidate? in
            guard let source = icon["src"] as? String,
                let url = URL(string: source, relativeTo: manifestURL)?.absoluteURL,
                isHTTPFamily(url)
            else { return nil }
            // Manifest-only maskable and monochrome assets are installation
            // resources, not general browser chrome. Their safe-zone padding or
            // single-color glyph can look broken when used as a tab favicon.
            // The Web App Manifest default is `any` when purpose is omitted.
            let purposes = Set(
                (icon["purpose"] as? String ?? "any")
                    .lowercased()
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
            )
            guard purposes.contains("any") else { return nil }
            let sizes = (icon["sizes"] as? String ?? "")
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
            let maximumSize =
                sizes
                .compactMap { Int($0.split(separator: "x").first ?? "") }
                .max() ?? 0
            let type = (icon["type"] as? String)?.lowercased()
            let isScalable =
                sizes.contains("any")
                || type == "image/svg+xml"
                || url.pathExtension.lowercased() == "svg"
            return ManifestIconCandidate(
                url: url,
                isScalable: isScalable,
                maximumSize: maximumSize,
                documentOrder: index
            )
        }
        .sorted { first, second in
            if first.isScalable != second.isScalable {
                return first.isScalable
            }
            if first.maximumSize != second.maximumSize {
                return first.maximumSize > second.maximumSize
            }
            return first.documentOrder < second.documentOrder
        }
        .map(\.url)
    }

    static func prioritizedCandidateURLs(
        discoveredIconURLs: [URL],
        manifestIconURLs: [URL],
        fallbackURL: URL?
    ) -> [URL] {
        var visited: Set<URL> = []
        return (manifestIconURLs + discoveredIconURLs + [fallbackURL].compactMap { $0 })
            .filter { visited.insert($0).inserted }
    }

    private static func resolvedURLs(
        _ value: Any?,
        relativeTo pageURL: URL
    ) -> [URL] {
        guard let strings = value as? [String] else { return [] }
        var visited: Set<URL> = []
        return strings.compactMap { string in
            guard let url = URL(string: string, relativeTo: pageURL)?.absoluteURL,
                isHTTPFamily(url) || url.scheme?.lowercased() == "data",
                visited.insert(url).inserted
            else { return nil }
            return url
        }
    }

    private static func resolvedIconURLs(
        _ value: Any?,
        relativeTo pageURL: URL
    ) -> [URL] {
        guard let values = value as? [[String: Any]] else {
            return resolvedURLs(value, relativeTo: pageURL)
        }
        let candidates = values.enumerated().compactMap {
            index,
            value -> IconCandidate? in
            guard let source = value["url"] as? String,
                let url = URL(string: source, relativeTo: pageURL)?.absoluteURL,
                isHTTPFamily(url) || url.scheme?.lowercased() == "data"
            else { return nil }
            let relationships = Set(
                (value["rel"] as? String ?? "")
                    .lowercased()
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
            )
            let isTouchIcon =
                relationships.contains("apple-touch-icon")
                || relationships.contains("apple-touch-icon-precomposed")
            let isBrowserIcon =
                !isTouchIcon
                && (relationships.contains("icon")
                    || relationships.contains("shortcut"))
            let maximumSize =
                (value["sizes"] as? String ?? "")
                .split(whereSeparator: \.isWhitespace)
                .compactMap { size in
                    Int(size.split(separator: "x").first ?? "")
                }
                .max() ?? 0
            return IconCandidate(
                url: url,
                preference: isBrowserIcon ? 1 : 0,
                maximumSize: maximumSize,
                documentOrder: index
            )
        }
        .sorted { first, second in
            if first.preference != second.preference {
                return first.preference > second.preference
            }
            if first.maximumSize != second.maximumSize {
                return first.maximumSize > second.maximumSize
            }
            return first.documentOrder < second.documentOrder
        }
        var visited: Set<URL> = []
        return candidates.compactMap { candidate in
            visited.insert(candidate.url).inserted ? candidate.url : nil
        }
    }

    private static func isHTTPFamily(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https"
            || url?.scheme?.lowercased() == "http"
    }

    private static let script = #"""
        const links = Array.from(document.querySelectorAll('link[rel][href]'));
        const icons = links
            .map((link) => {
                const rel = (link.rel || '').toLowerCase().split(/\s+/);
                if (!rel.some((token) => token === 'icon' || token === 'shortcut' || token === 'apple-touch-icon' || token === 'apple-touch-icon-precomposed')) {
                    return null;
                }
                return {
                    url: link.href,
                    rel: link.rel || '',
                    sizes: link.sizes?.value || ''
                };
            })
            .filter(Boolean);
        const manifests = Array.from(
            document.querySelectorAll('link[rel~="manifest"][href]')
        ).map((link) => link.href);
        return {
            icons,
            manifests: [...new Set(manifests)],
            userAgent: navigator.userAgent || ''
        };
        """#

    private static func normalizedUserAgent(_ value: String?) -> String? {
        guard let value,
            !value.isEmpty,
            value.utf8.count <= 1_024,
            !value.contains("\r"),
            !value.contains("\n")
        else { return nil }
        return value
    }

    private static let fetchResourceScript = #"""
        if (location.href !== pageURL) return null;
        const target = new URL(resourceURL);
        // Cross-origin public resources use the credential-free native loader.
        if (target.origin !== location.origin || target.username || target.password) return null;
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 12000);
        try {
            const response = await fetch(target.href, {
                credentials: 'same-origin',
                referrer: '',
                referrerPolicy: 'no-referrer',
                cache: 'no-store',
                headers: { Accept: accept },
                signal: controller.signal
            });
            if (!response.ok || !response.body) return null;
            const length = Number(response.headers.get('content-length'));
            if (length > maximumByteCount) return null;
            const reader = response.body.getReader();
            const chunks = [];
            let count = 0;
            while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                count += value.byteLength;
                if (count > maximumByteCount) return null;
                chunks.push(value);
            }
            if (!count) return null;
            let binary = '';
            for (const chunk of chunks) {
                for (let offset = 0; offset < chunk.length; offset += 8192) {
                    binary += String.fromCharCode(...chunk.subarray(offset, offset + 8192));
                }
            }
            return {
                base64: btoa(binary),
                mimeType: (response.headers.get('content-type') || '').split(';')[0].trim().toLowerCase(),
                url: response.url
            };
        } catch {
            return null;
        } finally {
            controller.abort();
            clearTimeout(timeout);
        }
        """#

    private static let rasterizeSVGScript = #"""
        const image = new Image();
        image.src = `data:image/svg+xml;base64,${svgBase64}`;
        await image.decode();
        const sourceWidth = Math.max(1, image.naturalWidth || maximumPixelSize);
        const sourceHeight = Math.max(1, image.naturalHeight || maximumPixelSize);
        const scale = maximumPixelSize / Math.max(sourceWidth, sourceHeight);
        const width = Math.max(1, Math.round(sourceWidth * scale));
        const height = Math.max(1, Math.round(sourceHeight * scale));
        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;
        const context = canvas.getContext('2d');
        if (!context) {
            throw new Error('Canvas 2D context is unavailable');
        }
        context.drawImage(image, 0, 0, width, height);
        return canvas.toDataURL('image/png');
        """#

    private static let maximumRasterizedPixelSize = 512

    private struct IconCandidate {
        let url: URL
        let preference: Int
        let maximumSize: Int
        let documentOrder: Int
    }

    private struct ManifestIconCandidate {
        let url: URL
        let isScalable: Bool
        let maximumSize: Int
        let documentOrder: Int
    }
}
