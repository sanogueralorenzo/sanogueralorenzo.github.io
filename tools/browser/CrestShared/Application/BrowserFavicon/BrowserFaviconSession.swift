import Foundation

@MainActor
final class BrowserFaviconSession {
    private let document: any BrowserFaviconDocument
    private let schedule: BrowserFaviconCaptureSchedule
    private let wait: @MainActor (Duration) async throws -> Void
    private let receive: (Data) -> Void
    private var generation: UInt64 = 0
    private var task: Task<Data?, Never>?
    private var requestedDocumentURL: URL?
    private var isStopped = false

    init(
        document: any BrowserFaviconDocument,
        policy schedule: BrowserFaviconCaptureSchedule = .immediate,
        wait: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        receive: @escaping (Data) -> Void
    ) {
        self.document = document
        self.schedule = schedule
        self.wait = wait
        self.receive = receive
    }

    deinit { task?.cancel() }

    func invalidate() {
        generation &+= 1
        task?.cancel()
        task = nil
        requestedDocumentURL = nil
    }

    func stop() {
        isStopped = true
        invalidate()
    }

    func refresh() {
        // Page reconciliation can repeat for every chrome update. A missing
        // icon is still a completed attempt; only navigation, icon changes,
        // or an explicit pull should start another discovery sequence.
        guard let url = document.url, requestedDocumentURL != url else { return }
        _ = start()
    }

    func pull() async -> Data? {
        guard !Task.isCancelled, let task = start() else { return nil }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func start() -> Task<Data?, Never>? {
        invalidate()
        guard !isStopped, let url = document.url else { return nil }
        requestedDocumentURL = url
        let requestGeneration = generation
        let document = document
        let schedule = schedule
        let wait = wait
        let task = Task { [weak self] in
            let isCurrent = { [weak self] in
                !Task.isCancelled && self?.generation == requestGeneration && document.url == url
            }
            let data = await Self.load(document, url: url, schedule: schedule, wait: wait, isCurrent: isCurrent)
            guard isCurrent() else {
                if Task.isCancelled, self?.generation == requestGeneration {
                    self?.task = nil
                    self?.requestedDocumentURL = nil
                }
                return nil as Data?
            }
            self?.task = nil
            if let data { self?.receive(data) }
            return data
        }
        self.task = task
        return task
    }

    private static func load(
        _ document: any BrowserFaviconDocument,
        url: URL,
        schedule: BrowserFaviconCaptureSchedule,
        wait: @MainActor (Duration) async throws -> Void,
        isCurrent: () -> Bool
    ) async -> Data? {
        guard isCurrent() else { return nil }
        let captured = await document.capture()
        guard isCurrent() else { return nil }
        if let captured { return captured }

        let fallback = await document.fallback(for: url)
        guard isCurrent() else { return nil }
        if let fallback { return fallback }

        for delay in schedule.retryDelays {
            do { try await wait(delay) } catch { return nil }
            guard isCurrent() else { return nil }
            let captured = await document.capture()
            guard isCurrent() else { return nil }
            if let captured { return captured }
        }
        return nil
    }
}
