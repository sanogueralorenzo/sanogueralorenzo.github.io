import Foundation
import Observation

@Observable
@MainActor
final class BrowserReaderModeSession {
    private(set) var state = BrowserReaderModeState.unavailable

    @ObservationIgnored private let document: any BrowserReaderModeDocument
    @ObservationIgnored private var generation = 0

    init(document: any BrowserReaderModeDocument) {
        self.document = document
    }

    func invalidate() {
        generation &+= 1
        state = .unavailable
    }

    func refreshAvailability() async {
        guard !state.isActive, state != .activating else { return }
        generation &+= 1
        let requestGeneration = generation
        let navigationURL = document.url
        guard navigationURL != nil else {
            state = .unavailable
            return
        }

        state = .checking
        do {
            let isAvailable = try await document.readerModeIsAvailable()
            try validate(requestGeneration, url: navigationURL)
            state = isAvailable ? .available : .unavailable
        } catch {
            guard isCurrent(requestGeneration, url: navigationURL) else { return }
            state = .unavailable
        }
    }

    func setActive(_ isActive: Bool) async throws {
        try Task.checkCancellation()
        generation &+= 1
        let requestGeneration = generation
        let navigationURL = document.url
        do {
            try await document.prepareForReaderMode()
            try validate(requestGeneration, url: navigationURL)
            guard navigationURL != nil else {
                state = .unavailable
                throw BrowserReaderModeError.articleUnavailable
            }

            if isActive {
                if state != .available {
                    let isAvailable = try await document.readerModeIsAvailable()
                    try validate(requestGeneration, url: navigationURL)
                    guard isAvailable else {
                        state = .unavailable
                        throw BrowserReaderModeError.articleUnavailable
                    }
                }
                state = .activating
                try await document.activateReaderMode()
                try validate(requestGeneration, url: navigationURL)
                state = .active
            } else {
                try await document.deactivateReaderMode()
                try validate(requestGeneration, url: navigationURL)
                let isAvailable = try await document.readerModeIsAvailable()
                try validate(requestGeneration, url: navigationURL)
                state = isAvailable ? .available : .unavailable
            }
        } catch {
            if isCurrent(requestGeneration, url: navigationURL),
                state == .activating || state == .checking
            {
                state = .unavailable
            }
            throw error
        }
    }

    func toggle() {
        let shouldActivate = !state.isActive
        Task { [weak self] in
            try? await self?.setActive(shouldActivate)
        }
    }

    private func validate(_ requestGeneration: Int, url: URL?) throws {
        try Task.checkCancellation()
        guard isCurrent(requestGeneration, url: url) else {
            throw BrowserReaderModeError.presentationFailed
        }
    }

    private func isCurrent(_ requestGeneration: Int, url: URL?) -> Bool {
        requestGeneration == generation && url == document.url
    }
}
