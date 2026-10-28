import SwiftUI

struct BrowserSpaceDeletionSection: View {
    let browser: BrowserStore
    let spaceID: UUID
    let dataDeleter: any BrowserSpaceDataDeleting

    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button(
                isDeleting ? "Deleting Space…" : "Delete “\(spaceName)”",
                role: .destructive
            ) {
                deleteSpace()
            }
            .disabled(isDeleting || browser.isDeleting(spaceID) || browser.spaceModels.count <= 1)
            .accessibilityIdentifier("delete-selected-space")

            if isDeleting {
                ProgressView("Removing private browser data…")
                    .accessibilityIdentifier("space-deletion-progress")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("space-deletion-error")
            }

        } footer: {
            Text(disclosure)
                .crestFormFootnote()
                .accessibilityIdentifier("space-deletion-disclosure")
        }
    }

    private var spaceName: String {
        browser.spaceModel(spaceID)?.settings.name ?? "Space"
    }

    private var disclosure: String {
        if browser.spaceModels.count <= 1 {
            return String(localized: "Crest needs at least one Space.")
        }
        return String(localized: "Deletes everything in this Space except downloaded files.")
    }

    private func deleteSpace() {
        errorMessage = nil
        isDeleting = true
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                try await browser.deleteSpace(
                    spaceID,
                    dataDeleter: dataDeleter
                )
            } catch {
                errorMessage = "\(error.localizedDescription) The Space was kept so you can try again."
            }
        }
    }
}
