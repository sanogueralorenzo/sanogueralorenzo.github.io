import SwiftUI
import UIKit

/// The share sheet's Crest entry. It hosts the share view and hands the shared
/// link to Crest by opening a `crest://open` URL.
final class CrestShareViewController: UIViewController {
    // MARK: - Variables

    private var model: CrestShareModel?
    private var hasReceivedItems = false

    // MARK: - Actions - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let model = CrestShareModel(
            open: { [weak self] url in await self?.open(url) ?? false },
            finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        )
        self.model = model

        let host = UIHostingController(rootView: CrestShareView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    /// Reads the shared items once the sheet is on screen, since only then
    /// does the responder chain reach the application that opens Crest.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasReceivedItems, let model else { return }
        hasReceivedItems = true
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task { await model.receive(providers) }
    }

    // MARK: - Actions - Opening links

    /// Opens `url` through the application that presents the share sheet.
    /// The system gives share extensions no API to open their app, so this
    /// walks the responder chain to the application and calls its
    /// `open(_:options:completionHandler:)` by selector. When a release
    /// closes that path it answers false and the sheet says so.
    private func open(_ url: URL) async -> Bool {
        typealias OpenURL =
            @convention(c) (
                AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
            ) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.isKind(of: UIApplication.self), current.responds(to: selector),
                let implementation = current.method(for: selector)
            {
                let open = unsafeBitCast(implementation, to: OpenURL.self)
                return await withCheckedContinuation { continuation in
                    open(current, selector, url as NSURL, NSDictionary()) { opened in
                        continuation.resume(returning: opened)
                    }
                }
            }
            responder = current.next
        }
        return false
    }
}
