import CrestCoreABI
import Foundation
import OSLog

extension CrestCore {
    // MARK: - Static Variables

    private static let pagesLogger = Logger(subsystem: "com.pauldavis.crest", category: "Pages")

    // MARK: - Actions - Site engines

    /// Opens `origin`'s pages on `engine` from now on, as a choice made in
    /// `spaceID`, and moves page `pageID` there, which loads what it showed.
    /// False when a rule refuses either, such as a locked Space or a page
    /// that is gone.
    @discardableResult
    func open(_ origin: SiteOrigin, in spaceID: UUID, on engine: EngineKind, moving pageID: UUID) -> Bool {
        do {
            guard let page = state.pages[pageID], page.spaceID == spaceID,
                page.live.address.flatMap({ URL(string: $0) }).flatMap({ SiteOrigin(url: $0) }) == origin
            else { return false }
            try send(RehostPage(pageID: pageID, engine: engine, remembersSite: true))
            return true
        } catch {
            Self.pagesLogger.debug(
                "The core kept page \(pageID, privacy: .public) on its engine: \(String(describing: error))")
            return false
        }
    }

    // MARK: - Actions - Engines

    /// Registers an engine with the core and answers the core's handle for it.
    /// The core runs the engine's commands through `relay` on the thread that
    /// sent the intent or report that caused them, which is the main thread.
    func registerEngine(_ registration: EngineRegistration, relay: Engines.Relay) throws(Rejection) -> UInt64 {
        var writer = WireWriter()
        registration.encode(into: &writer)
        var engine: UInt64 = 0
        var refusal = crest_buffer_t()
        var binding = crest_engine_binding_t(
            context: Unmanaged.passUnretained(relay).toOpaque(), attach: nil, run: relayEngineCommand)
        let status = CoreCodec.engineFingerprint.withUnsafeBufferPointer { fingerprint in
            writer.bytes.withUnsafeBufferPointer { settings in
                crest_engine_register(
                    handle, fingerprint.baseAddress, fingerprint.count, settings.baseAddress, settings.count, &binding,
                    &engine, &refusal)
            }
        }
        defer { crest_buffer_free(&refusal) }
        switch status {
        case CREST_OK:
            return engine
        case CREST_REJECTED:
            throw Self.rejection(in: refusal)
        default:
            Self.buildBug(status, "register an engine")
        }
    }

    /// Registers an engine whose binding the core runs directly, through the
    /// binding's own function table, and answers the core's handle for it.
    /// The binding reports to the core itself. `fingerprint` names the engine
    /// contract the binding was built against.
    func registerEngine(_ registration: EngineRegistration, table: crest_engine_binding_t, fingerprint: [UInt8])
        throws(Rejection) -> UInt64
    {
        var writer = WireWriter()
        registration.encode(into: &writer)
        var engine: UInt64 = 0
        var refusal = crest_buffer_t()
        var binding = table
        let status = fingerprint.withUnsafeBufferPointer { fingerprint in
            writer.bytes.withUnsafeBufferPointer { settings in
                crest_engine_register(
                    handle, fingerprint.baseAddress, fingerprint.count, settings.baseAddress, settings.count, &binding,
                    &engine, &refusal)
            }
        }
        defer { crest_buffer_free(&refusal) }
        switch status {
        case CREST_OK:
            return engine
        case CREST_REJECTED:
            throw Self.rejection(in: refusal)
        case CREST_VERSION_MISMATCH:
            preconditionFailure("The engine was built against another engine contract. Rebuild or download the engine.")
        default:
            Self.buildBug(status, "register an engine")
        }
    }

    /// Reports what happened to one of an engine's pages. What it changed
    /// arrives with the next drain.
    func report(_ event: some EngineEvent, engine: UInt64) {
        var writer = WireWriter()
        event.encodeEngineEvent(into: &writer)
        let status = writer.bytes.withUnsafeBufferPointer {
            crest_engine_report(handle, engine, $0.baseAddress, $0.count)
        }
        guard status == CREST_OK else { Self.buildBug(status, "take \(type(of: event)) from an engine") }
    }

    /// Answers what an engine asks about one of its pages while the engine
    /// waits, from the core's state as it stands, changing nothing.
    func ask<Question: EngineQuestion>(_ question: Question, engine: UInt64) -> Question.Answer {
        var writer = WireWriter()
        question.encodeEngineQuestion(into: &writer)
        let answer = EngineAnswer()
        let status = writer.bytes.withUnsafeBufferPointer {
            crest_engine_ask(
                handle, engine, $0.baseAddress, $0.count, receiveEngineAnswer,
                Unmanaged.passUnretained(answer).toOpaque())
        }
        guard status == CREST_OK, let bytes = answer.bytes else { Self.buildBug(status, "answer \(Question.self)") }
        var reader = WireReader(bytes)
        do {
            let decoded = try Question.decodeAnswer(from: &reader)
            try reader.finish()
            return decoded
        } catch {
            preconditionFailure("The core's answer to \(Question.self) does not decode (\(error)). Rebuild the core.")
        }
    }
}

/// The core's answer callback. It runs once, inside `crest_engine_ask`, on the
/// thread that asked.
private func receiveEngineAnswer(_ context: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int) {
    guard let context else { return }
    let answer = Unmanaged<EngineAnswer>.fromOpaque(context).takeUnretainedValue()
    answer.bytes = bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? []
}

/// The core's command callback. It runs on the main thread, which sends every
/// intent and report, outside every core lock.
private func relayEngineCommand(_ context: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int) {
    guard let context else { return }
    let relay = Unmanaged<Engines.Relay>.fromOpaque(context).takeUnretainedValue()
    var reader = WireReader(bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? [])
    let command: EngineCommand
    do {
        command = try EngineCommand(from: &reader)
        try reader.finish()
    } catch {
        preconditionFailure("The core's engine command does not decode (\(error)). Rebuild the core.")
    }
    MainActor.assumeIsolated { relay.engines?.run(command, on: relay.kind) }
}
