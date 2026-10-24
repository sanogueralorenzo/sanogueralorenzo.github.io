using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A text field of a synced record, as every client reads it: never empty, at
/// most `Limit` bytes of UTF-8 and, for some fields, of one form. Staging fits
/// each such field of every record it writes. Text past the limit is cut at the
/// last whole character that fits. Empty or unreadable text takes what the app
/// shows in its place, or is left out where a record without the field reads
/// the same. The session keeps what it holds; only its records are fitted.
internal sealed class SyncedText {
    #region Static Variables

    /// A Space's name. A Space the session holds unnamed is shown as this.
    public static readonly SyncedText SpaceName = new(field: "name", limit: 128, standIn: _ => "Your Space");
    public static readonly SyncedText SpaceSymbol = new(field: "symbol", limit: 128, standIn: _ => SpaceTemplate.Ordinary.Symbol);
    /// A split's name; a split without one shows its default name.
    public static readonly SyncedText SplitTitle = new(field: "customTitle", limit: 2_048, standIn: _ => null);
    /// A split's icon, which is an emoji or none.
    public static readonly SyncedText SplitIcon = new(field: "customIconSymbol", limit: 128, standIn: _ => null,
        reads: symbol => EmojiIcon.Parse(symbol) is not null);
    /// A folder's title. A folder the session holds untitled is shown as this.
    public static readonly SyncedText FolderTitle = new(field: "title", limit: 512, standIn: _ => StoredSessionCodec.UntitledFolder);
    /// A folder's symbol; a folder without one wears the folder symbol.
    public static readonly SyncedText FolderSymbol = new(field: "symbol", limit: 128, standIn: _ => null);
    /// A tab's page title. A page that named itself nothing is shown by its host.
    public static readonly SyncedText TabTitle = new(field: "title", limit: 2_048, standIn: Host);
    /// A tab's rename; a blank one is none, and the tab shows its page title.
    public static readonly SyncedText TabCustomTitle = new(field: "customTitle", limit: 2_048, standIn: _ => null);
    public static readonly SyncedText TabSymbol = new(field: "symbol", limit: 128, standIn: _ => TabIconMode.WebSymbol);
    /// A visit's page title. A page that named itself nothing is shown by its host.
    public static readonly SyncedText HistoryTitle = new(field: "title", limit: 2_048, standIn: Host);

    public static IReadOnlyList<SyncedText> All { get; } = [
        SpaceName, SpaceSymbol, SplitTitle, SplitIcon, FolderTitle, FolderSymbol, TabTitle, TabCustomTitle, TabSymbol, HistoryTitle
    ];

    #endregion

    #region Variables

    /// The record's member that holds the text.
    public string Field { get; }

    /// The most UTF-8 bytes a client reads in the field.
    public int Limit { get; }

    /// What the record carries when the session's text is empty or unreadable,
    /// read from the record's other members; null leaves the field out.
    private readonly Func<JsonObject, string?> standIn;

    /// Whether a client reads the text in the field, beyond its length.
    private readonly Func<string, bool> reads;

    #endregion

    #region Constructors

    private SyncedText(string field, int limit, Func<JsonObject, string?> standIn, Func<string, bool>? reads = null) {
        Field = field;
        Limit = limit;
        this.standIn = standIn;
        this.reads = reads ?? (_ => true);
    }

    #endregion

    #region Actions - Fitting

    /// Fits this field of `value`, a record's payload value, as every client
    /// reads it. A record without the field is left as it is.
    public void Fit(JsonObject value) {
        if (value[Field] is not JsonValue current || !current.TryGetValue<string>(out var text)) return;
        var fitted = Readable(Truncated(text));
        if (fitted is null && standIn(value) is { } substitute) fitted = Readable(Truncated(substitute));
        if (fitted == text) return;
        if (fitted is null) value.Remove(Field);
        else value[Field] = fitted;
    }

    /// `text`, when a client reads it in this field.
    private string? Readable(string text) => text.Length > 0 && reads(text) ? text : null;

    /// `text` cut after the last whole character that keeps it within the limit.
    private string Truncated(string text) {
        if (Encoding.UTF8.GetByteCount(text) <= Limit) return text;
        var characters = StringInfo.GetTextElementEnumerator(text);
        int bytes = 0, end = 0;
        while (characters.MoveNext()) {
            var character = characters.GetTextElement();
            bytes += Encoding.UTF8.GetByteCount(character);
            if (bytes > Limit) break;
            end = characters.ElementIndex + character.Length;
        }
        return text[..end];
    }

    /// The host of the record's address, or the address when it names none.
    private static string? Host(JsonObject value) {
        if (value["url"] is not JsonValue address || !address.TryGetValue<string>(out var url)) return null;
        return Uri.TryCreate(url, UriKind.Absolute, out var parsed) && parsed.Host.Length > 0 ? parsed.Host : url;
    }

    #endregion
}
