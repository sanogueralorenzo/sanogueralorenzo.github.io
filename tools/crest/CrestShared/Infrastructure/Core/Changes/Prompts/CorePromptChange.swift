import Foundation

/// A question the core asks the person, or the end of one. Once its batch is
/// applied, `CrestCore` hands it to every prompt host, and it shows itself on
/// each by calling the host's method for its kind.
protocol CorePromptChange: CoreChange {
    @MainActor func present(on host: any CorePromptHost)
}

/// Shows the questions the core asks the person, and closes each once the
/// core settles it. Each engine shows those its pages ask, the download
/// prompts those about downloads, and the quit preparation the one about
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
