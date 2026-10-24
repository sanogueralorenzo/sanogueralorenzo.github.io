import SwiftUI

struct BrowserPeekKeyboardMonitor: NSViewRepresentable {
    let dismiss: () -> Void
    let installsMonitor: Bool

    init(
        dismiss: @escaping () -> Void,
        installsMonitor: Bool = true
    ) {
        self.dismiss = dismiss
        self.installsMonitor = installsMonitor
    }

    func makeCoordinator() -> BrowserPeekKeyboardMonitorCoordinator {
        BrowserPeekKeyboardMonitorCoordinator(
            dismiss: dismiss,
            installsMonitor: installsMonitor
        )
    }

    func makeNSView(context: Context) -> BrowserPeekWindowTrackingView {
        let view = BrowserPeekWindowTrackingView()
        view.onWindowChange = { [weak coordinator = context.coordinator] windowNumber in
            coordinator?.windowNumber = windowNumber
        }
        context.coordinator.install()
        return view
    }

    func updateNSView(
        _ view: BrowserPeekWindowTrackingView,
        context: Context
    ) {
        context.coordinator.installsMonitor = installsMonitor
        context.coordinator.dismiss = dismiss
        context.coordinator.windowNumber = view.window?.windowNumber
    }

    static func dismantleNSView(
        _ view: BrowserPeekWindowTrackingView,
        coordinator: BrowserPeekKeyboardMonitorCoordinator
    ) {
        view.onWindowChange = nil
        coordinator.stop()
    }
}
