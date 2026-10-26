namespace CrestCore.Contracts;

/// The palette's fixed result groups, optional address completion, Google suggestions address,
/// offered local scope and any @ scope entered by the text. Private windows never request suggestions.
public sealed record PaletteAnswer(IReadOnlyList<PaletteGroup> Groups, AddressCompletion? Completion, string? SuggestionAddress,
    PaletteScope? OfferedScope, PaletteEntry? Entry);

/// A local @ scope and the text that follows it.
public sealed record PaletteEntry(PaletteScope Scope, string Text);

/// Completes what a person typed, `Typed`, as an address the Space already
/// knows: `Suffix` follows the text as typed, and accepting the completion
/// leaves `Accepted`, the address it opens, which may name a scheme or a
/// `www.` the person did not type.
public sealed record AddressCompletion(string Typed, string Suffix, string Accepted);

/// Rows of one section of the palette, in the order it ranked them.
public sealed record PaletteGroup(PaletteSection Section, IReadOnlyList<PaletteRow> Rows);

/// One thing the palette offers. Activating it shows `TabId`, opens `Address`,
/// performs `Command`, opens the settings page
/// `SettingsPage` or narrows to `Scope`, whichever it names. `SubjectId` is
/// what the row stands for when that is not its target: the folder a folder
/// row opens the first tab of, a history entry, a Space to switch to or an
/// archived tab to reopen. A search row names the provider it searches with
/// in `Provider`. `Symbol` is the SF Symbol the row wears when no tab icon or
/// provider icon stands for it. `Reason` says why the row ranked where it did.
public sealed record PaletteRow(PaletteRowKind Kind, string Title, string Subtitle, string Symbol, Guid? SubjectId, Guid? TabId,
    string? Address, ShortcutCommand? Command, SearchProvider? Provider, string? SettingsPage, PaletteScope? Scope, PaletteReason? Reason) {
    #region Constructors

    /// A row of `kind` with only what it names, wearing its kind's symbol
    /// unless it names its own.
    internal static PaletteRow Of(PaletteRowKind kind, string title, string subtitle, string? symbol = null, Guid? subject = null,
        Guid? tab = null, string? address = null, ShortcutCommand? command = null, SearchProvider? provider = null, string? page = null,
        PaletteScope? scope = null, PaletteReason? reason = null) =>
        new(kind, title, subtitle, symbol ?? kind.Symbol, subject, tab, address, command, provider, page, scope, reason);

    #endregion
}

/// A command the palette may offer, with the title and section title the
/// platform shows for it, which ranking matches what a person types against.
public sealed record PaletteCommand(ShortcutCommand Command, string Title, string SectionTitle);

/// A settings page the palette may open, named as the platform's settings name
/// it, with its title and the words a person might type to find it.
public sealed record PaletteSettingsPage(string Name, string Title, string Terms);
