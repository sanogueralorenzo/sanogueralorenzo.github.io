import AppKit
import Observation
import SwiftUI

/// The desktop's download destination for one Space, and the system touches
/// behind changing it.
///
/// `NSOpenPanel` and the security-scoped bookmark behind a remembered folder are
/// both AppKit, and the sentence under the controls names this Mac, so all of it
/// stays in this target. ``BrowserSpaceDownloadsSection`` draws whatever
/// ``settings(for:)`` hands back, which is the only thing the shared pane knows
/// about downloads.
@Observable
@MainActor
final class BrowserSpaceDownloadSettingsModel {
    private static let systemDirectoryName = "Downloads"

    private(set) var asksWhereToSave = false
    private(set) var directoryName = BrowserSpaceDownloadSettingsModel
        .systemDirectoryName
    private(set) var usesCustomDirectory = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let preferences: BrowserPlatformDownloadPreferences

    init(preferences: BrowserPlatformDownloadPreferences = .shared) {
        self.preferences = preferences
    }

    /// The section's whole input for one Space, rebuilt as the Space changes.
    func settings(for space: SpaceModel) -> BrowserSpaceDownloadSettings {
        BrowserSpaceDownloadSettings(
            asksWhereToSave: Binding { [self] in
                asksWhereToSave
            } set: { [self] enabled in
                setAsksWhereToSave(enabled, for: space.id)
            },
            directoryName: directoryName,
            usesCustomDirectory: usesCustomDirectory,
            errorMessage: errorMessage,
            chooseDirectory: { [self] in chooseDirectory(for: space) },
            resetDirectory: { [self] in resetDirectory(for: space.id) }
        )
    }

    func refresh(for spaceID: UUID) {
        asksWhereToSave = preferences.asksWhereToSave(for: spaceID)
        if let customName = preferences.directoryDisplayName(for: spaceID) {
            directoryName = customName
            usesCustomDirectory = true
        } else {
            directoryName = Self.systemDirectoryName
            usesCustomDirectory = false
        }
    }

    private func setAsksWhereToSave(_ enabled: Bool, for spaceID: UUID) {
        asksWhereToSave = enabled
        preferences.setAsksWhereToSave(enabled, for: spaceID)
    }

    private func chooseDirectory(for space: SpaceModel) {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Folder for \(space.settings.name)"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true

        Task { @MainActor in
            let response = await withCheckedContinuation { continuation in
                panel.begin { continuation.resume(returning: $0) }
            }
            guard response == .OK, let directory = panel.url else { return }
            do {
                try preferences.rememberDirectory(directory, for: space.id)
                errorMessage = nil
                refresh(for: space.id)
            } catch {
                errorMessage = "Crest couldn’t retain access to this folder."
            }
        }
    }

    private func resetDirectory(for spaceID: UUID) {
        preferences.clearDirectory(for: spaceID)
        errorMessage = nil
        refresh(for: spaceID)
    }
}
