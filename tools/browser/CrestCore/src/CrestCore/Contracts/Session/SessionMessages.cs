namespace CrestCore.Contracts;

#region Queries

/// Whether an intent would be accepted: `Refusal` names the rule that would
/// refuse it, or is null when the core would accept it.
public sealed record SendPermission(Rejection? Refusal);

#endregion

#region Rejections

/// A name is longer than `Limit` characters, or blank where one is required.
public sealed record InvalidName(int Limit) : Rejection;

/// The workspace already holds an open tab with this identity.
public sealed record TabAlreadyExists(Guid TabId) : Rejection;

/// The Space already holds `Limit` tabs, so it takes no more.
public sealed record TabLimitReached(int Limit) : Rejection;

/// The Space holds no tab with this identity.
public sealed record UnknownTab(Guid TabId) : Rejection;

/// `Url` names nothing a page can load: not an address a tab may show, nor
/// words to search for.
public sealed record UnsupportedAddress(string Url) : Rejection;

/// Another change to the workspace is being saved. The intent changed nothing
/// and may be sent again.
public sealed record WorkspaceBusy(Guid WorkspaceId) : Rejection;

#endregion

#region Models - Spaces

/// <summary>Whether a Space opens freely or asks the device owner to authenticate first.</summary>
public enum SpaceAccessPolicy { Open, DeviceOwnerAuthentication }

/// <summary>A Space deletion under way on this device, identified by its operation.
/// The Space and its profile stay untouched until the device has erased the profile's
/// data and removed the Space. It never becomes a sync record.</summary>
public sealed record SpaceDeletionState(Guid Id, Guid SpaceId, Guid ProfileId);

#endregion

#region Models - Tabs

/// <summary>A tab in its Space's archive, when it arrived there and why.</summary>
public sealed record ArchivedTabState(TabState Tab, DateTimeOffset ArchivedAt, ArchiveReason Reason);

/// <summary>A native view a tab shows instead of a web page. <see cref="Kind"/> stays
/// open so a view another build added survives here; <see cref="ResourceId"/> names a
/// separately stored document the view shows.</summary>
public sealed record NativeTabContent(string Kind, Guid? ResourceId = null);

/// <summary>The color a tab's icon sits on, taken from its page. Components run 0 through 1.</summary>
public sealed record TabIconAccent(double Red, double Green, double Blue);

#endregion

#region Models - Preferences

/// <summary>Whether a Space offers to save and fill passwords, and where it keeps them.</summary>
public sealed record CredentialPreferences(bool IsEnabled, bool SyncsCrestPasswordsWithICloud, bool AlsoOffersSaveToSystemPasswords);

/// <summary>How long a Space keeps its history, archived tabs and downloads.</summary>
public sealed record DataRetentionPreferences(DataRetention History, DataRetention Archive, DataRetention Downloads);

/// <summary>A source language's chosen destination. Disabling keeps the destination.</summary>
public sealed record TranslationRule(string SourceLanguage, string TargetId, bool IsEnabled);

#endregion

#region Models - Colors

/// <summary>A color a person chose for a Space, folder or split. Components run 0 through 1.</summary>
public sealed record BrandColor(double Red, double Green, double Blue, double Alpha = 1);

/// A system color a set's presentation tints a symbol with. Each platform maps
/// it to its own color once. A tint travels as its value, so new tints go last.
public enum SystemTint { Red, Orange, Purple, Blue, Indigo, Teal, Pink, Green }

#endregion
