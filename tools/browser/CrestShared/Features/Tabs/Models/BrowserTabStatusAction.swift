import SwiftUI

/// Something a tab's status mark does: the action of a mark's button, or one
/// item of its menu. Each carries its title and symbol, so every menu item
/// has an icon.
@MainActor
struct BrowserTabStatusAction {
    // MARK: - Static Variables

    static let mute = Self(
        title: LocalizedStringResource("Mute Tab", comment: "Mutes the sound a tab's page plays."),
        symbol: "speaker.slash"
    ) { $0.setMuted(true) }

    static let unmute = Self(
        title: LocalizedStringResource("Unmute Tab", comment: "Unmutes the sound a tab's page plays."),
        symbol: "speaker.wave.2"
    ) { $0.setMuted(false) }

    static let goToSharingTab = Self(
        title: LocalizedStringResource("Go to Sharing Tab", comment: "Shows the tab whose page shares this tab."),
        symbol: "arrow.forward.square",
        isAvailable: { $0.sharingCounterpart != nil },
        perform: { $0.showSharingCounterpart() }
    )

    static let goToSharedTab = Self(
        title: LocalizedStringResource("Go to Shared Tab", comment: "Shows the tab this tab's page shares."),
        symbol: "arrow.forward.square",
        isAvailable: { $0.sharingCounterpart != nil },
        perform: { $0.showSharingCounterpart() }
    )

    static let stopSharing = Self(
        title: LocalizedStringResource("Stop Sharing", comment: "Stops the tab sharing a tab takes part in."),
        symbol: "stop.circle",
        role: .destructive
    ) { $0.stopSharing() }

    #if os(macOS)
        static let stopAgent = Self(
            title: LocalizedStringResource(
                "Stop Agent in This Tab", comment: "Stops the agent using a tab from using it."),
            symbol: "hand.raised",
            role: .destructive
        ) { $0.stopAgent() }

        static let disconnectAgent = Self(
            title: LocalizedStringResource(
                "Disconnect Agent", comment: "Disconnects the agent using a tab from Crest."),
            symbol: "xmark.circle",
            role: .destructive
        ) { $0.disconnectAgent() }
    #endif

    // MARK: - Variables

    let title: LocalizedStringResource
    let symbol: String
    let role: ButtonRole?

    /// Whether the action can act on the tab now. An action that cannot is
    /// left out of its mark.
    let isAvailable: @MainActor (BrowserTabStatusSource) -> Bool

    private let perform: @MainActor (BrowserTabStatusSource) -> Void

    // MARK: - Initializers

    private init(
        title: LocalizedStringResource,
        symbol: String,
        role: ButtonRole? = nil,
        isAvailable: @escaping @MainActor (BrowserTabStatusSource) -> Bool = { _ in true },
        perform: @escaping @MainActor (BrowserTabStatusSource) -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.isAvailable = isAvailable
        self.perform = perform
    }

    // MARK: - Actions - Running

    /// Does the action for the tab, while the row or tile drawing its mark may
    /// act and the action still can.
    func run(on tab: BrowserTabStatusSource) {
        guard tab.canAct(), isAvailable(tab) else { return }
        perform(tab)
    }
}
