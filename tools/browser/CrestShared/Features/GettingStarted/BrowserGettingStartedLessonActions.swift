import SwiftUI

// The practice actions the guides offer for the tabs chapter's lessons. Each
// guide switches on the lesson's kind to choose one of these concrete views.

/// Pins the practice Gmail tab.
struct BrowserGettingStartedPinAction: View {
    let practice: BrowserGettingStartedPractice

    var body: some View {
        Button("Pin Gmail", systemImage: "pin.fill") {
            if let mail = practice.tabID(.mail) { practice.browser.pinTab(mail) }
        }
        .buttonStyle(.crestPrimary(tint: CrestBrandPalette.butter))
    }
}

/// Saves the practice trail tab, worded the way each guide words it.
struct BrowserGettingStartedSaveAction: View {
    let practice: BrowserGettingStartedPractice
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Button(title, systemImage: systemImage) {
            if let trail = practice.tabID(.trail) { practice.browser.saveTab(trail) }
        }
        .buttonStyle(.crestPrimary(tint: CrestBrandPalette.butter))
    }
}

/// Adds a practice folder, and one nested inside it. The two buttons join the
/// guide's own stack, so each guide lays them out its way.
struct BrowserGettingStartedFolderActions: View {
    let practice: BrowserGettingStartedPractice

    var body: some View {
        Button("Add folder", systemImage: "folder.badge.plus") { practice.addFolder(nested: false) }
            .buttonStyle(.crestSecondary)
        Button("Nest a folder", systemImage: "folder") { practice.addFolder(nested: true) }
            .buttonStyle(.crestSecondary)
    }
}

/// Points to Clear on the practice sidebar's line, where a pointer reaches it.
struct BrowserGettingStartedClearHint: View {
    var body: some View {
        Text("Use Clear on the line in the practice sidebar.")
            .font(CrestTypography.sans(12)).foregroundStyle(.secondary)
    }
}

/// Archives the practice Space's open tabs, as its ••• menu does.
struct BrowserGettingStartedCleanUpAction: View {
    let practice: BrowserGettingStartedPractice

    var body: some View {
        Button("Clean Up Current Tabs", systemImage: "sparkles") {
            _ = practice.tabActions.clearCurrentTabs()
        }
        .buttonStyle(.crestPrimary(tint: CrestBrandPalette.butter))
    }
}
