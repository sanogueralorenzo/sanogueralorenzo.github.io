namespace CrestCore.Contracts;

/// Whether the device has passkeys set up, as far as the platform can tell. A
/// configuration travels as its index in `All`, so `All` is append-only.
public sealed class PasskeyDeviceConfiguration {
    #region Static Variables

    public static readonly PasskeyDeviceConfiguration Configured = new(name: "configured", rulesOutPasskeys: false);
    public static readonly PasskeyDeviceConfiguration NotConfigured = new(name: "notConfigured", rulesOutPasskeys: true);
    public static readonly PasskeyDeviceConfiguration Unknown = new(name: "unknown", rulesOutPasskeys: false);

    public static IReadOnlyList<PasskeyDeviceConfiguration> All { get; } = [Configured, NotConfigured, Unknown];

    #endregion

    #region Variables

    public string Name { get; }

    /// The platform knows the device has no passkeys set up, so websites
    /// cannot use them until the person sets them up.
    public bool RulesOutPasskeys { get; }

    #endregion

    #region Constructors

    private PasskeyDeviceConfiguration(string name, bool rulesOutPasskeys) {
        Name = name;
        RulesOutPasskeys = rulesOutPasskeys;
    }

    #endregion

    #region Actions - Lookup

    public static PasskeyDeviceConfiguration? Named(string? name) => All.FirstOrDefault(configuration => configuration.Name == name);

    #endregion
}
