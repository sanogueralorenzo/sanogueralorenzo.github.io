import Foundation

/// A transient message at the top of a browser window. It asks nothing of the
/// person: anything that needs a decision is a dialog, and everything else
/// that Crest reports — a copy, a zoom change, an action that could not run —
/// is one of these. It may offer one action that undoes what it reports, such
/// as moving a page back to the engine it left.
struct BrowserNotice: Equatable, Hashable {
    let message: String
    let systemImage: String
    var action: BrowserNoticeAction?

    static let urlCopied = BrowserNotice(
        message: String(localized: "URL Copied"),
        systemImage: "checkmark.circle.fill"
    )

    static let copied = BrowserNotice(
        message: String(localized: "Copied"),
        systemImage: "checkmark.circle.fill"
    )

    static func pageZoom(_ label: String) -> BrowserNotice {
        BrowserNotice(message: label, systemImage: "textformat.size")
    }

    /// Long enough to read: short confirmations leave quickly, sentences stay,
    /// and one that offers an action stays longest, so the person can take it.
    var duration: Duration {
        guard action == nil else { return BrowserRootMetrics.noticeLongestDuration }
        let reading = Duration.milliseconds(message.count * 60)
        return min(max(BrowserRootMetrics.noticeDuration, reading), BrowserRootMetrics.noticeLongestDuration)
    }
}

/// The one action a notice offers. Each is its own, so two notices with the
/// same words stay two notices.
struct BrowserNoticeAction: Equatable, Hashable {
    private let id = UUID()
    let title: String
    let perform: @MainActor () -> Void

    init(title: String, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.perform = perform
    }

    static func == (lhs: BrowserNoticeAction, rhs: BrowserNoticeAction) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Delivers notices to the window the person is looking at, for callers that
/// do not hold a window's chrome: engine toasts, extension actions, page
/// services. The most recently focused window stands in when none is key.
@MainActor
final class BrowserNoticeCenter {
    static let shared = BrowserNoticeCenter()

    private struct Receiver {
        weak var chrome: BrowserChromeState?
        let isFocused: @MainActor () -> Bool
    }
    private var receivers: [Receiver] = []

    func register(_ chrome: BrowserChromeState, isFocused: @escaping @MainActor () -> Bool) {
        receivers.removeAll { $0.chrome == nil || $0.chrome === chrome }
        receivers.append(Receiver(chrome: chrome, isFocused: isFocused))
    }

    func post(_ notice: BrowserNotice) {
        receivers.removeAll { $0.chrome == nil }
        let target = receivers.last(where: { $0.isFocused() }) ?? receivers.last
        target?.chrome?.showNotice(notice)
    }
}
