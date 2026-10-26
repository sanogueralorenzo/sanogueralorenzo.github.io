using System.Globalization;
using System.Text;

namespace CrestCore.Contracts;

/// An emoji chosen as an icon, which a symbol spells as `crest.emoji:` and
/// the emoji. Every client reads the first character after the prefix, once
/// trimmed, and takes it only when that character presents as an emoji: one of
/// its code points has the Unicode `Emoji_Presentation` property, or it holds
/// the emoji variation selector or the combining keycap.
public readonly record struct EmojiIcon {
    #region Static Variables

    private const int VariationSelector = 0xFE0F;
    private const int Keycap = 0x20E3;

    /// The code points with `Emoji_Presentation`, as the Apple clients' Unicode
    /// data names them, first to last in each range.
    private static readonly (int First, int Last)[] Presentation = [
        (0x231A, 0x231B), (0x23E9, 0x23EC), (0x23F0, 0x23F0), (0x23F3, 0x23F3), (0x25FD, 0x25FE), (0x2614, 0x2615),
        (0x2648, 0x2653), (0x267F, 0x267F), (0x2693, 0x2693), (0x26A1, 0x26A1), (0x26AA, 0x26AB), (0x26BD, 0x26BE),
        (0x26C4, 0x26C5), (0x26CE, 0x26CE), (0x26D4, 0x26D4), (0x26EA, 0x26EA), (0x26F2, 0x26F3), (0x26F5, 0x26F5),
        (0x26FA, 0x26FA), (0x26FD, 0x26FD), (0x2705, 0x2705), (0x270A, 0x270B), (0x2728, 0x2728), (0x274C, 0x274C),
        (0x274E, 0x274E), (0x2753, 0x2755), (0x2757, 0x2757), (0x2795, 0x2797), (0x27B0, 0x27B0), (0x27BF, 0x27BF),
        (0x2B1B, 0x2B1C), (0x2B50, 0x2B50), (0x2B55, 0x2B55), (0x1F004, 0x1F004), (0x1F0CF, 0x1F0CF),
        (0x1F18E, 0x1F18E), (0x1F191, 0x1F19A), (0x1F1E6, 0x1F1FF), (0x1F201, 0x1F201), (0x1F21A, 0x1F21A),
        (0x1F22F, 0x1F22F), (0x1F232, 0x1F236), (0x1F238, 0x1F23A), (0x1F250, 0x1F251), (0x1F300, 0x1F320),
        (0x1F32D, 0x1F335), (0x1F337, 0x1F37C), (0x1F37E, 0x1F393), (0x1F3A0, 0x1F3CA), (0x1F3CF, 0x1F3D3),
        (0x1F3E0, 0x1F3F0), (0x1F3F4, 0x1F3F4), (0x1F3F8, 0x1F43E), (0x1F440, 0x1F440), (0x1F442, 0x1F4FC),
        (0x1F4FF, 0x1F53D), (0x1F54B, 0x1F54E), (0x1F550, 0x1F567), (0x1F57A, 0x1F57A), (0x1F595, 0x1F596),
        (0x1F5A4, 0x1F5A4), (0x1F5FB, 0x1F64F), (0x1F680, 0x1F6C5), (0x1F6CC, 0x1F6CC), (0x1F6D0, 0x1F6D2),
        (0x1F6D5, 0x1F6D8), (0x1F6DC, 0x1F6DF), (0x1F6EB, 0x1F6EC), (0x1F6F4, 0x1F6FC), (0x1F7E0, 0x1F7EB),
        (0x1F7F0, 0x1F7F0), (0x1F90C, 0x1F93A), (0x1F93C, 0x1F945), (0x1F947, 0x1F9FF), (0x1FA70, 0x1FA7C),
        (0x1FA80, 0x1FA8A), (0x1FA8E, 0x1FAC6), (0x1FAC8, 0x1FAC8), (0x1FACD, 0x1FADC), (0x1FADF, 0x1FAEA),
        (0x1FAEF, 0x1FAF8)
    ];

    #endregion

    #region Variables

    /// The emoji: one character.
    public string Emoji { get; }

    /// How a symbol slot spells the emoji.
    public string Symbol => TabIconMode.EmojiPrefix + Emoji;

    #endregion

    #region Constructors

    private EmojiIcon(string emoji) => Emoji = emoji;

    #endregion

    #region Actions - Reading

    /// The emoji `symbol` spells, or null when it spells none a client reads.
    public static EmojiIcon? Parse(string? symbol) {
        if (symbol is null || !symbol.StartsWith(TabIconMode.EmojiPrefix, StringComparison.Ordinal)) return null;
        string rest = symbol[TabIconMode.EmojiPrefix.Length..].Trim();
        if (rest.Length == 0) return null;
        string character = StringInfo.GetNextTextElement(rest);
        return character.EnumerateRunes().Any(rune => PresentsAsEmoji(rune.Value)) ? new EmojiIcon(character) : null;
    }

    /// The emoji a person chose, given as the emoji itself or already spelled
    /// as a symbol, or null when its first character does not present as one.
    public static EmojiIcon? Chosen(string? text) =>
        text is null ? null : Parse(text.StartsWith(TabIconMode.EmojiPrefix, StringComparison.Ordinal) ? text : TabIconMode.EmojiPrefix + text);

    private static bool PresentsAsEmoji(int scalar) =>
        scalar is VariationSelector or Keycap || Presentation.Any(range => scalar >= range.First && scalar <= range.Last);

    #endregion
}
