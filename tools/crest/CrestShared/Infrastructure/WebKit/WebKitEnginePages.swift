import ImageIO
import UniformTypeIdentifiers
import WebKit

/// WebKit's direct path from the platform to the pages its binding built: it
/// answers each page request against the page's web view, and presents what
/// finishes later, such as a find's count or a capture, to the page that
/// asked. What WebKit keeps nothing of, such as blocked popups or its own
/// bars, it answers that nothing was done.
@MainActor
final class WebKitEnginePages: EnginePages {
    // MARK: - Variables

    private unowned let binding: WebKitEngineBinding
    /// The pages that hear the presentations about them.
    private var attached = AttachedEnginePages()
    #if os(macOS)
        /// What agents the person allowed do in the binding's pages.
        private(set) lazy var agents = WebKitPageAgents(pages: self) { [weak self] presentation in
            self?.attached.present(presentation)
        }
    #endif

    // MARK: - Initializers

    init(binding: WebKitEngineBinding) {
        self.binding = binding
    }

    // MARK: - Actions - Requests

    func attach(_ page: EnginePage) {
        attached.attach(page)
    }

    /// Answers `request` for one of the binding's pages, as the request's own
    /// `answer(on:)` says. One for a page that is gone answers that nothing
    /// was done.
    @discardableResult
    func request<Request: PageRequest>(_ request: Request) -> Request.Answer {
        request.answer(on: self)
    }

    /// The binding's page `pageID` names, while its owner keeps it.
    func page(_ pageID: UUID) -> WebKitEnginePage? {
        binding.page(pageID)
    }

    // MARK: - Actions - Documents

    /// Snapshots what the page's web view shows, and presents it as a PNG
    /// once WebKit has it.
    func capture(_ capturing: CapturePage) -> Bool {
        #if os(macOS)
            guard let page = page(capturing.pageID) else { return false }
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = false
            if let area = capturing.area {
                configuration.rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
            }
            if capturing.width > 0 { configuration.snapshotWidth = NSNumber(value: capturing.width) }
            page.webView.takeSnapshot(with: configuration) { [weak self] image, _ in
                MainActor.assumeIsolated {
                    self?.present(image) { png in
                        .pageCaptured(PageCaptured(pageID: capturing.pageID, captureID: capturing.captureID, png: png))
                    }
                }
            }
            return true
        #else
            return false
        #endif
    }

    /// Makes the page's document as the export asks, and presents it once
    /// WebKit made it.
    func export(_ exporting: ExportPage) -> Bool {
        #if os(macOS)
            guard let page = page(exporting.pageID) else { return false }
            return export(exporting, from: page)
        #else
            return false
        #endif
    }

    /// The certificates the page's current document was verified with, the
    /// leaf first.
    func certificates(_ page: WebKitEnginePage) -> [Data] {
        guard let trust = page.webView.serverTrust,
            let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        else { return [] }
        return chain.map { SecCertificateCopyData($0) as Data }
    }

    #if os(macOS)
        private static func webArchive(of webView: WKWebView) async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                webView.createWebArchiveData { continuation.resume(with: $0) }
            }
        }

        /// The whole document as a PNG, `width` points wide or as wide as it
        /// lays out, up to 1,600 points; within 6,000 by 24,000 points.
        private static func fullPage(of webView: WKWebView, width requestedWidth: Double) async -> Data? {
            let measured = try? await webView.evaluateJavaScript(
                """
                (() => {
                  const root = document.documentElement;
                  const body = document.body;
                  return [
                    Math.max(root?.scrollWidth ?? 0, body?.scrollWidth ?? 0, innerWidth),
                    Math.max(root?.scrollHeight ?? 0, body?.scrollHeight ?? 0, innerHeight)
                  ];
                })()
                """
            )
            guard let dimensions = measured as? [NSNumber], dimensions.count == 2 else { return nil }
            let width = min(max(CGFloat(dimensions[0].doubleValue), webView.bounds.width), 6_000)
            let height = min(max(CGFloat(dimensions[1].doubleValue), webView.bounds.height), 24_000)
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
            configuration.afterScreenUpdates = true
            configuration.snapshotWidth = NSNumber(value: requestedWidth > 0 ? requestedWidth : min(width, 1_600))
            guard let image = try? await webView.takeSnapshot(configuration: configuration),
                let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return nil }
            let scale = CGFloat(bitmap.width) / max(image.size.width, 1)
            return await Task.detached(priority: .userInitiated) { Self.png(bitmap, scale: scale) }.value
        }

        /// Presents `image` as a PNG once it is encoded away from the main
        /// thread, which encoding a whole view's pixels would hold up.
        private func present(_ image: NSImage?, as presentation: @escaping @MainActor (Data?) -> EnginePresentation) {
            guard let image, let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                attached.present(presentation(nil))
                return
            }
            let scale = CGFloat(bitmap.width) / max(image.size.width, 1)
            Task { @MainActor [weak self] in
                let png = await Task.detached(priority: .userInitiated) { Self.png(bitmap, scale: scale) }.value
                self?.attached.present(presentation(png))
            }
        }

        /// Presents the document `make` makes for the export once it is made.
        private func export(_ exporting: ExportPage, making make: @escaping @MainActor () async -> Data?) -> Bool {
            Task { @MainActor [weak self] in
                let document = await make()
                self?.attached.present(
                    .pageExported(
                        PageExported(
                            pageID: exporting.pageID, exportID: exporting.exportID, document: document,
                            failure: document == nil ? .failed : nil)))
            }
            return true
        }
    #endif

    /// `image` as a PNG that names its own resolution, so it opens at the
    /// size in points WebKit drew it at.
    private nonisolated static func png(_ image: CGImage, scale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let resolution = 72 * max(scale, 1)
        let properties = [kCGImagePropertyDPIWidth: resolution, kCGImagePropertyDPIHeight: resolution] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: - Actions - Inspector

    func openInspector(_ opening: OpenInspector) -> Bool {
        #if os(macOS)
            guard let webView = page(opening.pageID)?.webView else { return false }
            return BrowserWebInspectorAccess.open(
                opening.panel, inspectorOwner: webView, isInspectable: webView.isInspectable)
        #else
            return false
        #endif
    }

    func closeInspector(_ pageID: UUID) -> Bool {
        #if os(macOS)
            guard let webView = page(pageID)?.webView else { return false }
            return BrowserWebInspectorAccess.close(inspectorOwner: webView)
        #else
            return false
        #endif
    }

    func isInspected(_ pageID: UUID) -> Bool {
        #if os(macOS)
            guard let webView = page(pageID)?.webView else { return false }
            return BrowserWebInspectorAccess.isVisible(inspectorOwner: webView)
        #else
            return false
        #endif
    }

    // MARK: - Actions - Sites

    /// WebKit has no popup blocker of its own to tell: the page's preferences
    /// carry Crest's popup decision. Crest's own prompts enforce the rest.
    func setSitePermission(_ setting: SetSitePermission) -> Bool {
        guard setting.permission == .popups, let page = page(setting.pageID) else { return false }
        page.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = setting.allowed == true
        return true
    }

    /// WebKit leaves capture running after Crest withdraws a grant; Crest's
    /// own prompt decided it, so Crest ends it.
    func stopCapture(_ stopping: StopMediaCapture) -> Bool {
        guard let webView = page(stopping.pageID)?.webView else { return false }
        if stopping.permission.devices.contains(.camera) {
            webView.setCameraCaptureState(.none, completionHandler: nil)
        }
        if stopping.permission.devices.contains(.microphone) {
            webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        }
        return true
    }

    /// What media the page ran when WebKit last answered, and the Picture in
    /// Picture it reported since.
    func mediaActivity(_ page: WebKitEnginePage) -> PageMediaActivity {
        page.engine.hasVideoInPictureInPicture
            ? page.engine.knownMediaActivity.union(.pictureInPicture) : page.engine.knownMediaActivity
    }

    // MARK: - Actions - Find

    /// Finds text in the page, and presents its count once WebKit has it.
    func find(_ finding: FindInPage) -> Bool {
        guard let page = page(finding.pageID) else { return false }
        let configuration = BrowserFindConfiguration(backwards: finding.backwards, caseSensitive: finding.caseSensitive)
        page.webView.performFind(finding.query, configuration: configuration) { [weak self] result in
            // WebKit tells only whether it found a match, never how many.
            let finished = FindFinished(pageID: finding.pageID, matches: result.matchFound ? nil : 0, activeMatch: 0)
            self?.attached.present(.findFinished(finished))
        }
        return true
    }
}

#if os(macOS)
    extension WebKitEnginePages {
        /// Makes `page`'s document in the export's format. Answers whether
        /// the export began; WebKit makes no MHTML.
        private func export(_ exporting: ExportPage, from page: WebKitEnginePage) -> Bool {
            switch exporting.format {
            case .pdf: exportPDF(exporting, from: page)
            case .png: exportPNG(exporting, from: page)
            case .mhtml: exportMHTML(exporting, from: page)
            case .webArchive: exportWebArchive(exporting, from: page)
            }
        }

        private func exportPDF(_ exporting: ExportPage, from page: WebKitEnginePage) -> Bool {
            let webView = page.webView
            return export(exporting) { try? await webView.pdf(configuration: WKPDFConfiguration()) }
        }

        private func exportPNG(_ exporting: ExportPage, from page: WebKitEnginePage) -> Bool {
            let webView = page.webView
            return export(exporting) { await Self.fullPage(of: webView, width: exporting.width) }
        }

        /// WebKit keeps its archives as web archives, never as MHTML.
        private func exportMHTML(_ exporting: ExportPage, from page: WebKitEnginePage) -> Bool {
            false
        }

        private func exportWebArchive(_ exporting: ExportPage, from page: WebKitEnginePage) -> Bool {
            let webView = page.webView
            return export(exporting) { try? await Self.webArchive(of: webView) }
        }
    }
#endif
