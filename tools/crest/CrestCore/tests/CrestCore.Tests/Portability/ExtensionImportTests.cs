using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The extensions a Chromium browser offers to install again: only those
/// installed from the Chrome Web Store and still turned on, named as the
/// person sees them, offered by each Space the browser brings, and left on or
/// off in the review.
public sealed partial class BrowserContractsTests {
    private const string Ublock = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
    private const string Dark = "eimadpbcbfnmbkopoojfekhnkhdbieeh";
    private const string Hidden = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    /// The settings of an extension, with `inManifest` added inside its manifest.
    private static string Extension(string id, string name, string inManifest = "", string location = "1", string fromStore = "true",
        string? state = "1", string disableReasons = "0") =>
        "\"" + id + "\":{\"location\":" + location + ",\"from_webstore\":" + fromStore + (state is null ? "" : ",\"state\":" + state)
        + ",\"disable_reasons\":" + disableReasons + ",\"manifest\":{\"name\":\"" + name + "\",\"version\":\"1.0\"" + inManifest + "}}";

    /// A settings file holding `entries`.
    private static string Settings(string entries) => "{\"extensions\":{\"settings\":{" + entries + "}}}";

    /// A Chromium profile whose settings files hold `secure` and `plain`.
    private static ImportFolder Profile(BrowserDataFolder folder, string secure, string? plain = null) {
        folder.Write(Path.Combine("Default", "Secure Preferences"), Settings(secure));
        if (plain is not null) folder.Write(Path.Combine("Default", "Preferences"), Settings(plain));
        return new(Path.Combine(folder.Path, "Default"));
    }

    [Fact]
    public void OnlyEnabledWebStoreExtensionsAreOfferedByName() {
        using var chrome = new BrowserDataFolder();
        var profile = Profile(chrome, string.Join(",", [
            Extension(Ublock, "uBlock Origin"),
            Extension(Dark, "dark reader"),
            // Turned off, loaded from a folder, not from the store, built in, a theme, an app or not an identifier.
            Extension("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "Off", state: "0"),
            Extension("cccccccccccccccccccccccccccccccc", "Reasons", disableReasons: "1"),
            Extension("dddddddddddddddddddddddddddddddd", "Unpacked", location: "4"),
            Extension("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", "Sideloaded", fromStore: "false"),
            Extension("ffffffffffffffffffffffffffffffff", "Built in", location: "5"),
            Extension("gggggggggggggggggggggggggggggggg", "Theme", inManifest: ",\"theme\":{}"),
            Extension("hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh", "App", inManifest: ",\"app\":{}"),
            Extension("not-an-identifier", "Bad")
        ]));

        // By name, ignoring case.
        Assert.Equal([new ImportExtension(Dark, "dark reader"), new ImportExtension(Ublock, "uBlock Origin")], ChromiumExtensions.Read(profile));
    }

}
