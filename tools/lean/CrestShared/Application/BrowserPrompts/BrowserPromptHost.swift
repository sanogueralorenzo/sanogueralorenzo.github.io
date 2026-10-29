import Foundation

/// A question or its settlement, delivered to the native presentation hosts.
/// Each host presents the kinds of question it handles.
protocol CorePromptChange: Sendable {
    @MainActor func present(on host: any CorePromptHost)
}

/// Shows questions and closes each once the browser settles it. WebKit shows
/// those its pages ask, the download prompts those about downloads, and quit
/// preparation the one about
/// downloads in progress. Every host answers each kind of question
/// explicitly, with an empty method for a kind another host shows, so a
/// misspelled method cannot silently show nothing; every host closes what
/// it showed.
@MainActor
protocol CorePromptHost: AnyObject {
    func ask(_ asked: ScriptDialogAsked)
    func ask(_ asked: AuthenticationAsked)
    func ask(_ asked: PermissionAsked)
    func ask(_ asked: ExtensionInstallAsked)
    func ask(_ asked: DownloadDestinationAsked)
    func ask(_ asked: DownloadApprovalAsked)
    func ask(_ asked: QuitWithDownloadsAsked)
    func dismiss(_ settled: PromptSettled)
}
