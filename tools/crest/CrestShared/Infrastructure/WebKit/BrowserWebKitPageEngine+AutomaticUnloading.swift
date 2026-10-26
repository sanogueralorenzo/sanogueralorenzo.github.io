import Foundation
import WebKit

extension BrowserWebKitPageEngine {
    // MARK: - Static Variables

    /// Protect edits conservatively, including accessible child frames. An
    /// inaccessible frame or an oversized document stays loaded.
    private static let automaticUnloadCheck = #"""
        const pending = [window];
        let inspected = 0;
        while (pending.length) {
            if (++inspected > 100) return false;
            const frame = pending.pop();
            try {
                const doc = frame.document;
                if (!doc || doc.readyState !== 'complete' || typeof frame.onbeforeunload === 'function') return false;
                const controls = doc.querySelectorAll('input, textarea, select, [contenteditable]');
                if (controls.length > 5000) return false;
                for (const control of controls) {
                    if (control.isContentEditable && control.textContent.trim()) return false;
                    if (control.tagName === 'TEXTAREA' && control.value !== control.defaultValue) return false;
                    if (control.tagName === 'INPUT') {
                        if (control.type === 'file' && control.files.length) return false;
                        if (['checkbox', 'radio'].includes(control.type)) {
                            if (control.checked !== control.defaultChecked) return false;
                        } else if (!['hidden', 'submit', 'reset', 'button', 'image'].includes(control.type)
                            && control.value !== control.defaultValue) return false;
                    }
                    if (control.tagName === 'SELECT') {
                        const options = Array.from(control.options);
                        const explicit = options.some(option => option.defaultSelected);
                        if (options.some((option, index) => option.selected !==
                            (explicit ? option.defaultSelected : !control.multiple && index === 0))) return false;
                    }
                }
                for (const child of doc.querySelectorAll('iframe, frame')) {
                    if (!child.contentWindow) return false;
                    pending.push(child.contentWindow);
                }
            } catch (_) { return false; }
        }
        return true;
        """#

    // MARK: - Actions - Automatic unloading

    func canAutomaticallyUnload() async -> Bool {
        guard !Task.isCancelled, await mediaActivity() == PageMediaActivity() else { return false }
        do {
            let clean = try await webView.callAsyncJavaScript(
                Self.automaticUnloadCheck, arguments: [:], in: nil, contentWorld: .page)
            guard clean as? Bool == true, !Task.isCancelled else { return false }
        } catch { return false }
        #if os(macOS)
            // WebKit also checks listeners registered through addEventListener.
            // A request to stay is declined without showing a dialog.
            return await withCheckedContinuation { continuation in
                prepareToClose(automatically: true) { continuation.resume(returning: $0) }
            }
        #else
            return true
        #endif
    }
}
