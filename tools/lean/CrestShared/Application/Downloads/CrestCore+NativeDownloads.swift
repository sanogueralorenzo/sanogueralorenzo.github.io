import Foundation

extension CrestCore {
    @discardableResult
    func send(_ intent: some DownloadIntent) throws(DownloadLedgerError) -> [UUID] { try downloads.send(intent) }

    nonisolated func query<Question: DownloadQuery>(_ question: Question) throws(DownloadLedgerError) -> Question.Answer
    {
        try question.answer()
    }

    nonisolated static func answer<Question: DownloadQuery>(_ question: Question) throws(DownloadLedgerError)
        -> Question.Answer
    {
        try question.answer()
    }
}

extension WebKitEngineBinding {
    func report(_ event: EngineDownloadChanged) { core?.downloads.report(event, from: self) }
    func report(_ event: EngineDownloadDestinationRequested) { core?.downloads.report(event, from: self) }
}
