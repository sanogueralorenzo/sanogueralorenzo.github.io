namespace CrestCore.Contracts;

/// Something the core asks one engine binding to do with a page. The core
/// delivers commands in the order it issued them, never while it holds a lock
/// and never on the stack of the report that caused them.
public abstract record EngineCommand;

#region Pages

/// Makes the page the engine offered as `OfferId` the page `PageId` names,
/// which the core opened for a tab, in the profile `ProfileId` names and the
/// window `WindowId` names. A private page keeps nothing once it closes. The
/// binding answers with `PageCreated`, or `PageCreationFailed` when the offer
/// is gone.
public sealed record AdoptOfferedPage(Guid PageId, Guid OfferId, Guid ProfileId, bool IsPrivate, Guid WindowId)
    : EngineCommand;

/// Closes the engine's page for a page its owner released. `KeepsState` says
/// the owner kept what it needs to bring the page back later, so the page was
/// unloaded rather than closed for good. The binding answers with `PageClosed`.
public sealed record ClosePage(Guid PageId, bool KeepsState) : EngineCommand;

/// Creates the engine's page for a page the core opened, in the profile of the
/// page's Space, hosted by the window `WindowId` names. A private page keeps
/// nothing once it closes, and shares nothing with any other Space: its
/// profile is new each time private browsing opens. `RestoreState` is what an
/// earlier page of the same tab kept, which the new page restores instead of
/// loading anew. The binding answers with `PageCreated` or
/// `PageCreationFailed`.
public sealed record CreatePage(Guid PageId, Guid ProfileId, bool IsPrivate, Guid WindowId, PageRestoreState? RestoreState)
    : EngineCommand;

/// Ends the Picture in Picture of a page a window shows again, or of one whose
/// Space this process may not show, returning its video to its place in the
/// page, where it keeps playing. The binding ends only a Picture in Picture
/// the page holds, never another page's.
public sealed record ExitPictureInPicture(Guid PageId) : EngineCommand;

/// Shows the entry `EntryId` names in the page's back and forward history,
/// as the engine keeps the entry. The binding reports the navigation it
/// starts as it reports any other. An entry the engine no longer holds starts
/// nothing, and the binding reports the page's history again.
public sealed record GoToHistoryEntry(Guid PageId, Guid EntryId) : EngineCommand;

/// Loads `Url` in a page, as the core resolved it from what the person asked
/// for. The load is the app's own rather than the page content's, so it may
/// reach an address web content may not. The binding reports the navigation
/// it starts as it reports any other. With `EntryId`, the entry the load
/// commits takes that identity, so a history entry the engine no longer holds
/// comes back as itself.
public sealed record LoadPage(Guid PageId, string Url, Guid? EntryId = null) : EngineCommand;

/// Brings back the document a page showed when its renderer stopped, as the
/// core's crash recovery decided. The binding loads the page's current history
/// entry again, never posting a form a second time, and reports the navigation
/// it starts as it reports any other.
public sealed record RecoverPage(Guid PageId) : EngineCommand;

/// The page the engine offered as `OfferId` has no place in Crest, so the
/// engine closes it.
public sealed record RejectOfferedPage(Guid OfferId) : EngineCommand;

#endregion

#region Tab Groups

/// Makes the engine's tab group `GroupId` hold the pages `PageIds` names, in
/// that order, with `Title`, `Color` and its collapsed state, as the folder
/// that shows the group stands. A page the group holds that the list leaves
/// out leaves it, and an empty list takes out every page, which closes the
/// group. A group the engine no longer holds is made again with the same
/// identity, in the window of the first page, so an extension still finds it
/// under the identity it knew. A page the engine has no tab for is skipped.
/// The binding reports nothing of what it changes.
public sealed record GroupPages(Guid GroupId, string Title, TabGroupColor Color, bool IsCollapsed, IReadOnlyList<Guid> PageIds)
    : EngineCommand;

#endregion

#region Navigation

/// Forgets the link the engine staged as `StagedLinkId`, which no page will load.
public sealed record DropStagedLink(Guid StagedLinkId) : EngineCommand;

/// The first load of the page `PageId` names, when it loads `Url`, runs the
/// link its engine staged as `StagedLinkId`, keeping the referrer, initiator
/// and security the link had where it was followed. The binding reports
/// `StagedLinkUnavailable` when the link no longer applies.
public sealed record StageNavigation(Guid PageId, Guid StagedLinkId, string Url) : EngineCommand;

#endregion

#region Prompts

/// Asks a page whether it may go: its document may ask the person to stay.
/// The binding answers with `BeforeUnloadAnswered`, at once for a document
/// that asks nothing.
public sealed record CheckBeforeUnload(Guid PageId) : EngineCommand;

/// Answers a server's request with `Credential`, or cancels it with none.
public sealed record SettleAuthentication(Guid PromptId, AuthenticationCredential? Credential) : EngineCommand;

/// Installs the extension the prompt asked about, with its site access
/// withheld when asked, or cancels the install.
public sealed record SettleExtensionInstall(Guid PromptId, bool Accepted, bool WithholdsSiteAccess) : EngineCommand;

/// Answers a permission request: whether it `Grants` it, and whether the
/// answer holds for the site's later requests or this one alone. For a
/// capability the system asks about itself, a grant lets the request go on to
/// the system's question.
public sealed record SettlePermission(Guid PromptId, bool Grants, bool Remembers) : EngineCommand;

/// Closes a script dialog as the person answered it, or declined when no one
/// could.
public sealed record SettleScriptDialog(Guid PromptId, bool Accepted, string? Text) : EngineCommand;

#endregion

#region Downloads

/// Keeps a download the engine warned about, while its warning is still the
/// one `ApprovalToken` names.
public sealed record ApproveEngineDownload(Guid ProfileId, string DownloadId, string ApprovalToken) : EngineCommand;

/// Cancels an engine download.
public sealed record CancelEngineDownload(Guid ProfileId, string DownloadId) : EngineCommand;

/// Pauses a transfer without discarding the engine's saved request or partial file.
public sealed record PauseEngineDownload(Guid ProfileId, string DownloadId) : EngineCommand;

/// Resumes or restarts a download using the engine's saved request, when it permits recovery.
public sealed record ResumeEngineDownload(Guid ProfileId, string DownloadId) : EngineCommand;

/// Removes a finished or stopped engine download from the engine's list.
public sealed record RemoveEngineDownload(Guid ProfileId, string DownloadId) : EngineCommand;

/// The file a download the engine asked about goes to, or none to cancel it.
/// Choosing where a file goes never overrides the engine's safety verdict.
public sealed record SettleDownloadDestination(Guid PromptId, string? Path) : EngineCommand;

#endregion

#region Website Data

/// Erases everything the engine keeps for profile `ProfileId`, without
/// opening a page or starting anything the engine has not started. The
/// binding answers with `DataErased` for `ErasureId`.
public sealed record EraseProfileData(Guid ProfileId, bool Ephemeral, Guid ErasureId) : EngineCommand;

/// Erases what the engine keeps for profile `ProfileId` in `Categories` for the
/// site of each of `Hosts`, its registrable domain. Site data is its cookies,
/// its third parties' cookies and storage partitioned under it, its storage
/// and its service workers, which stop; the cache is the responses kept for
/// it. It creates no store the profile does not have; an `Ephemeral` one keeps
/// them only while it is open, and nothing on disk is touched. The binding
/// answers with `DataErased` for `ErasureId`, erased once none of it is left,
/// or nothing was there.
public sealed record EraseSiteData(Guid ProfileId, bool Ephemeral, IReadOnlyList<string> Hosts,
    IReadOnlyList<BrowsingDataCategory> Categories, Guid ErasureId) : EngineCommand;

/// Erases what the engine keeps for profile `ProfileId` in `Categories` that
/// changed since `Since`, or ever when it is nil. Web data only: what
/// extensions store stays. It creates no store the profile does not have. The
/// binding answers with `DataErased` for `ErasureId`.
public sealed record EraseBrowsingData(Guid ProfileId, bool Ephemeral, DateTimeOffset? Since,
    IReadOnlyList<BrowsingDataCategory> Categories, Guid ErasureId) : EngineCommand;

/// Lists the sites that keep data the engine holds for profile `ProfileId`,
/// without creating a store the profile does not have. The binding answers
/// with `SiteDataRead` for `ReadingId`.
public sealed record ReadSiteData(Guid ProfileId, bool Ephemeral, Guid ReadingId) : EngineCommand;

#endregion
