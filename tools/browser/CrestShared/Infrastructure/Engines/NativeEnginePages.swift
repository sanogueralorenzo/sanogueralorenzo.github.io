import CrestCoreABI
import Foundation

/// The platform's direct path to an engine binding written outside Swift, as
/// `EnginePage` uses it: requests for view work on a page, which the binding
/// answers at once, and the presentations it sends back when work finishes
/// later. Both cross the binding's `crest_engine_pages_t` table in the
/// generated wire format; the core never sees them.
@MainActor
final class NativeEnginePages: EnginePages {
    // MARK: - Variables

    private var table: crest_engine_pages_t?
    private var startingRequests: [[UInt8]] = []
    private var start: (@MainActor () -> Void)?
    /// Hears each presentation the binding sends.
    private let present: @MainActor (EnginePresentation) -> Void
    /// The pages that hear the presentations about them.
    private var attached = AttachedEnginePages()
    var isReady: Bool { table != nil }

    // MARK: - Initializers

    /// A path to the binding `table` names. The binding sends its
    /// presentations to `present` from now on; this object must outlive the
    /// binding, as the composition that owns it does.
    init(table: crest_engine_pages_t, present: @escaping @MainActor (EnginePresentation) -> Void) {
        self.present = present
        bind(table)
    }

    /// A registered engine can start after its first page is requested. View
    /// actions made while that runtime starts are replayed once it is ready.
    init(start: @escaping @MainActor () -> Void, present: @escaping @MainActor (EnginePresentation) -> Void) {
        self.start = start
        self.present = present
    }

    func bind(_ table: crest_engine_pages_t) {
        precondition(self.table == nil, "An engine's page binding attaches once per launch.")
        self.table = table
        start = nil
        guard let presentTo = table.present_to else {
            preconditionFailure("The engine binding has no way to present. Rebuild the engine.")
        }
        presentTo(table.context, receiveEnginePresentation, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Called after the engine's queued create commands, so watches and view
    /// actions find the pages those commands created.
    func replayStartingRequests() {
        guard let table, let send = table.request, let release = table.release else { return }
        let requests = startingRequests
        startingRequests = []
        for bytes in requests {
            var answer = crest_buffer_t()
            let status = bytes.withUnsafeBufferPointer { send(table.context, $0.baseAddress, $0.count, &answer) }
            release(table.context, &answer)
            precondition(status == CREST_OK, "The engine could not decode a queued page request.")
        }
    }

    // MARK: - Actions - Requests

    /// Asks the binding for `request` and answers what it answered.
    @discardableResult
    func request<Request: PageRequest>(_ request: Request) -> Request.Answer {
        var writer = WireWriter()
        request.encodePageRequest(into: &writer)
        guard let table else {
            // Only initial view setup may wait, such as the history a page
            // restores in place of its first load, which loads the page's
            // address when the engine cannot restore it. A refused user action
            // must never execute later after its caller was told it failed.
            precondition(Request.Answer.self == Bool.self, "\(type(of: request)) requires a ready engine.")
            let deferred = request is WatchPage || request is ZoomPage || request is RestoreInteractionState
            if deferred {
                startingRequests.append(writer.bytes)
                start?()
            }
            var reader = WireReader([deferred ? 1 : 0])
            do { return try Request.decodeAnswer(from: &reader) } catch {
                preconditionFailure("A Boolean page action has an invalid answer codec.")
            }
        }
        guard let send = table.request, let release = table.release else {
            preconditionFailure("The engine binding takes no requests. Rebuild the engine.")
        }
        var answer = crest_buffer_t()
        let status = writer.bytes.withUnsafeBufferPointer { bytes in
            send(table.context, bytes.baseAddress, bytes.count, &answer)
        }
        defer { release(table.context, &answer) }
        guard status == CREST_OK else {
            preconditionFailure("The engine binding refused \(type(of: request)) (\(status)). Rebuild the engine.")
        }
        var reader = WireReader(answer.bytes.map { Array(UnsafeBufferPointer(start: $0, count: answer.length)) } ?? [])
        do {
            let value = try Request.decodeAnswer(from: &reader)
            try reader.finish()
            return value
        } catch {
            preconditionFailure(
                "The engine's answer to \(type(of: request)) does not decode (\(error)). Rebuild the engine.")
        }
    }

    func attach(_ page: EnginePage) {
        attached.attach(page)
    }

    // MARK: - Actions - Presentations

    fileprivate func receive(_ bytes: [UInt8]) {
        var reader = WireReader(bytes)
        let presentation: EnginePresentation
        do {
            presentation = try EnginePresentation(from: &reader)
            try reader.finish()
        } catch {
            preconditionFailure("The engine's presentation does not decode (\(error)). Rebuild the engine.")
        }
        attached.present(presentation)
        present(presentation)
    }
}

/// The binding's presentation callback. The binding presents on the thread
/// that makes requests, which is the main thread, never on a request's stack.
private func receiveEnginePresentation(_ ui: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int) {
    guard let ui else { return }
    let pages = Unmanaged<NativeEnginePages>.fromOpaque(ui).takeUnretainedValue()
    let message = bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? []
    MainActor.assumeIsolated { pages.receive(message) }
}
