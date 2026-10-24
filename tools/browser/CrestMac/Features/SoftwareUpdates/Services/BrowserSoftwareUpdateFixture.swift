import Foundation

/// An updater state an explicitly isolated verification launch presents,
/// named by the launch, after the update it offers.
struct BrowserSoftwareUpdateFixture: Sendable {
    // MARK: - Static Variables

    /// The offered update alone, also standing for any name Crest does not
    /// know.
    static let available = Self(name: "available") { _, _, _, _ in }
    static let checking = Self(name: "checking") { model, _, _, _ in
        model.presentChecking(cancellation: {})
    }
    static let automaticDownloading = Self(name: "automatic-downloading") { model, version, build, releaseNotes in
        model.presentAutomaticDownload(
            title: "Crest \(version)",
            version: version,
            build: build,
            releaseNotes: releaseNotes,
            informationURL: nil,
            isFixture: true
        )
    }
    static let downloading = Self(name: "downloading") { model, _, _, _ in
        model.presentDownload(cancellation: {})
        model.setExpectedDownloadLength(100)
        model.receiveDownloadedBytes(42)
    }
    static let automaticReady = Self(name: "automatic-ready") { model, version, build, releaseNotes in
        model.presentAutomaticUpdateReady(
            title: "Crest \(version)",
            version: version,
            build: build,
            releaseNotes: releaseNotes,
            informationURL: nil,
            isFixture: true,
            installAndRelaunch: { [weak model] in
                model?.presentInstalling(
                    applicationTerminated: true,
                    retryTermination: {}
                )
            }
        )
    }
    static let ready = Self(name: "ready") { model, _, _, _ in
        model.presentReadyToInstall(
            install: { [weak model] in
                model?.presentInstalling(
                    applicationTerminated: true,
                    retryTermination: {}
                )
            },
            cancel: {}
        )
    }
    static let failed = Self(name: "failed") { model, _, _, _ in
        model.presentError(
            message: "This isolated fixture simulates an update error.",
            acknowledgement: {}
        )
    }

    static let all: [BrowserSoftwareUpdateFixture] = [
        available, checking, automaticDownloading, downloading, automaticReady, ready, failed,
    ]

    // MARK: - Variables

    let name: String

    /// Presents the state on the model, which already offers the update with
    /// the version, build and release notes it is given.
    private let presentation:
        @MainActor @Sendable (
            _ model: BrowserSoftwareUpdateModel, _ version: String, _ build: String, _ releaseNotes: String
        ) -> Void

    // MARK: - Initializers

    private init(
        name: String,
        presentation:
            @escaping @MainActor @Sendable (
                _ model: BrowserSoftwareUpdateModel, _ version: String, _ build: String, _ releaseNotes: String
            ) -> Void
    ) {
        self.name = name
        self.presentation = presentation
    }

    // MARK: - Actions - Presenting

    /// The fixture a launch names, or `available` for a name Crest does not
    /// know.
    static func named(_ name: String) -> Self {
        all.first { $0.name == name } ?? available
    }

    /// Presents the fixture's state on `model`, which already offers the
    /// update with `version`, `build` and `releaseNotes`.
    @MainActor
    func present(on model: BrowserSoftwareUpdateModel, version: String, build: String, releaseNotes: String) {
        presentation(model, version, build, releaseNotes)
    }
}
