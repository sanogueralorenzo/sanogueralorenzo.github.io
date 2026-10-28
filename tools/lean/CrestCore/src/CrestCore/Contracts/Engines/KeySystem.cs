namespace CrestCore.Contracts;

/// A protected-media key system a page asks for that an engine playing
/// protected media through the platform stands in for. A key system travels
/// as its index in `All`, so `All` is append-only.
public sealed class KeySystem {
    #region Variables

    /// Google's Widevine, which Crest's Chromium does not carry.
    public static readonly KeySystem Widevine = new(name: "widevine");

    /// Microsoft's PlayReady, which Crest's Chromium does not carry.
    public static readonly KeySystem PlayReady = new(name: "playready");

    public static IReadOnlyList<KeySystem> All { get; } = [Widevine, PlayReady];

    public string Name { get; }

    #endregion

    #region Constructors

    private KeySystem(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static KeySystem? Named(string? name) => All.FirstOrDefault(system => system.Name == name);

    #endregion
}
