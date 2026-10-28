namespace CrestCore.Contracts;

#region Changes

/// A server's request for a user name and password waits on the person.
public sealed record AuthenticationAsked(Guid PromptId, Guid PageId, AuthenticationQuestion Question) : Change;

/// Whether to install an extension waits on the person, in the window that
/// started the install.
public sealed record ExtensionInstallAsked(Guid PromptId, Guid WindowId, ExtensionInstallQuestion Question) : Change;

/// A site's permission request that its Space's choices do not answer waits
/// on the person.
public sealed record PermissionAsked(Guid PromptId, Guid PageId, PermissionQuestion Question) : Change;

/// A prompt no longer waits: the person answered it, its engine withdrew it,
/// or its page went.
public sealed record PromptSettled(Guid PromptId) : Change;

/// A page's script dialog waits on the person.
public sealed record ScriptDialogAsked(Guid PromptId, Guid PageId, ScriptDialogQuestion Question) : Change;

#endregion

#region Rejections

/// The answer is not of the kind the prompt asks for.
public sealed record PromptAnswerMismatch(Guid PromptId) : Rejection;

/// The intent names a prompt that no longer waits.
public sealed record UnknownPrompt(Guid PromptId) : Rejection;

#endregion

#region Models

/// A server a page loads from asked for a user name and password: `Host` and
/// `Port` of `Url`, in `Realm`, with `Scheme`, after `PreviousFailures` wrong
/// answers.
public sealed record AuthenticationQuestion(string Url, string Host, int Port, string? Realm, AuthenticationScheme Scheme,
    bool IsProxy, int PreviousFailures);

/// The HTTP authentication schemes Crest answers.
public enum AuthenticationScheme {
    Basic,
    Digest
}

/// Whether to install the extension package the engine verified: its
/// `Name`, `Version` and `Summary`, the `Permissions` it asks for, as the
/// engine words them, and its icon as PNG bytes. `CanWithholdSiteAccess` says
/// the person may keep its site access back, and `WithholdsSiteAccess` says
/// installing does so unless they choose otherwise.
public sealed record ExtensionInstallQuestion(string ExtensionId, string Name, string Version, string Summary,
    IReadOnlyList<string> Permissions, byte[]? Icon, bool CanWithholdSiteAccess, bool WithholdsSiteAccess);

/// A document in a page asked for `Permission`, from `Origin` inside
/// `TopLevelOrigin`.
public sealed record PermissionQuestion(SitePermission Permission, SiteOrigin Origin, SiteOrigin TopLevelOrigin);

/// A document in a page opened a script dialog: an alert, a confirmation, a
/// prompt with `DefaultText`, or the question whether to leave the page.
/// `SourceUrl` is the address of the document that opened it.
public sealed record ScriptDialogQuestion(JavaScriptDialogKind Kind, string Message, string DefaultText, string SourceUrl);

/// The script dialogs a page can open.
public enum JavaScriptDialogKind {
    Alert,
    Confirm,
    Prompt,

    /// Whether to leave a page that asked to be kept.
    BeforeUnload
}

#endregion
