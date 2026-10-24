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

    [Fact]
    public void ADisabledExtensionIsLeftOutWhicheverWayChromeSpellsItsReasons() {
        using var chrome = new BrowserDataFolder();
        // Current Chromium keeps a list of reasons and no `state`; older versions kept a bitmask and a `state`.
        var profile = Profile(chrome, string.Join(",", [
            Extension(Ublock, "Listed reasons", state: null, disableReasons: "[1,4]"),
            Extension(Dark, "No reasons", state: null, disableReasons: "[]"),
            Extension("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "Bitmask", disableReasons: "5"),
            Extension("cccccccccccccccccccccccccccccccc", "Older enabled", disableReasons: "0"),
            Extension("dddddddddddddddddddddddddddddddd", "Older off", state: "0", disableReasons: "0")
        ]));

        Assert.Equal([new ImportExtension(Dark, "No reasons"), new ImportExtension("cccccccccccccccccccccccccccccccc", "Older enabled")],
            ChromiumExtensions.Read(profile));
    }

    [Fact]
    public void ThePlainPreferencesFillInAndTheSecureOnesWin() {
        using var chrome = new BrowserDataFolder();
        var profile = Profile(chrome, Extension(Ublock, "Secure Name"),
            string.Join(",", [Extension(Ublock, "Plain Name"), Extension(Dark, "Dark")]));

        // Preferences is read first and Secure Preferences last, so the secure spelling stands.
        Assert.Equal([new ImportExtension(Dark, "Dark"), new ImportExtension(Ublock, "Secure Name")], ChromiumExtensions.Read(profile));
    }

    [Fact]
    public void AMessageNameReadsFromTheExtensionsOwnLocaleFilesAndFallsBackToItsIdentifier() {
        using var chrome = new BrowserDataFolder();
        var profile = Profile(chrome, string.Join(",", [
            Extension(Ublock, "__MSG_extName__"),
            Extension(Dark, "__MSG_missing__"),
            """
            "ffffffffffffffffffffffffffffffff":{"location":1,"from_webstore":true,"state":1}
            """
        ]));
        chrome.Write(Path.Combine("Default", "Extensions", Ublock, "1.0_0", "_locales", "de", "messages.json"),
            """{"EXTNAME":{"message":"  Werbeblocker "}}""");
        chrome.Write(Path.Combine("Default", "Extensions", Ublock, "1.0_0", "manifest.json"), """{"name":"__MSG_extName__","default_locale":"de"}""");
        chrome.Write(Path.Combine("Default", "Extensions", "ffffffffffffffffffffffffffffffff", "2.0", "manifest.json"), """{"name":"From Manifest"}""");

        var found = ChromiumExtensions.Read(profile);
        // The locale is the manifest's default one; a message nothing defines leaves the raw name's identifier.
        Assert.Equal([new ImportExtension(Dark, Dark), new ImportExtension("ffffffffffffffffffffffffffffffff", "From Manifest"),
            new ImportExtension(Ublock, "Werbeblocker")], found);
    }

    [Fact]
    public void AnOfferWearsItsLargestToolbarIconFromInsideItsOwnFolder() {
        using var chrome = new BrowserDataFolder();
        var profile = Profile(chrome, string.Join(",", [
            Extension(Ublock, "uBlock Origin", inManifest: ",\"icons\":{\"16\":\"icons/16.png\",\"128\":\"/icons/128.png\",\"512\":\"icons/512.png\"}"),
            Extension(Dark, "Dark Reader", inManifest: ",\"icons\":{\"48\":\"../../../Secure Preferences\"}")
        ]));
        foreach (string size in new[] { "16", "128", "512" })
            chrome.Write(Path.Combine("Default", "Extensions", Ublock, "1.0_0", "icons", size + ".png"), "png");
        chrome.Write(Path.Combine("Default", "Extensions", Dark, "1.0_0", "manifest.json"), "{}");

        var found = ChromiumExtensions.Read(profile);
        // The largest up to 128 pixels; a path that leaves the extension's folder is no icon.
        Assert.Equal(Path.Combine(chrome.Path, "Default", "Extensions", Ublock, "1.0_0", "icons", "128.png"),
            found.Single(extension => extension.ExtensionId == Ublock).IconPath);
        Assert.Null(found.Single(extension => extension.ExtensionId == Dark).IconPath);
    }

    [Fact]
    public void AnExtensionAnotherStoreServesIsNotOfferedAndOperasSettingsAreRead() {
        using var opera = new BrowserDataFolder();
        opera.Write(Path.Combine("Default", "Secure Preferences"), "{\"extensions\":{\"settings\":{"
            + Extension(Ublock, "From the Web Store", inManifest: ",\"update_url\":\"https://clients2.google.com/service/update2/crx\"") + ","
            + Extension("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "From Edge Add-ons",
                inManifest: ",\"update_url\":\"https://edge.microsoft.com/extensionwebstorebase/v1/crx\"")
            + "},\"opsettings\":{" + Extension(Dark, "Kept by Opera") + "}}}");

        Assert.Equal([new ImportExtension(Ublock, "From the Web Store"), new ImportExtension(Dark, "Kept by Opera")],
            ChromiumExtensions.Read(new(Path.Combine(opera.Path, "Default"))));
    }

    [Fact]
    public void AProfileWithoutSettingsOffersNothingAndAnUnreadableOneIsSkipped() {
        using var chrome = new BrowserDataFolder();
        Assert.Empty(ChromiumExtensions.Read(new(Path.Combine(chrome.Path, "Default"))));
        chrome.Write(Path.Combine("Default", "Secure Preferences"), "not json");
        chrome.Write(Path.Combine("Default", "Preferences"), Settings(Extension(Ublock, "Kept")));
        Assert.Equal([new ImportExtension(Ublock, "Kept")], ChromiumExtensions.Read(new(Path.Combine(chrome.Path, "Default"))));
    }

    [Fact]
    public void EachChromeProfileOffersItsOwnExtensionsToItsSpace() {
        using var chrome = new BrowserDataFolder();
        string work = chrome.Write(Path.Combine("Default", "Bookmarks"), """{"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[{"type":"url","name":"A","url":"https://a.example/"}]}}}""");
        chrome.Write(Path.Combine("Default", "Secure Preferences"), Settings(Extension(Ublock, "uBlock Origin")));
        string home = chrome.Write(Path.Combine("Profile 1", "Bookmarks"), """{"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[{"type":"url","name":"B","url":"https://b.example/"}]}}}""");
        using var app = Importer();

        var imported = app.Query(new ReadImport(ImportSource.Chrome, [
            new("Default", "Work", work, null, Path.Combine(chrome.Path, "Default")),
            new("Profile 1", "Home", home, null, Path.Combine(chrome.Path, "Profile 1"))
        ]));

        // Home keeps no extension settings, so it offers none.
        var offer = Assert.Single(imported.Extensions);
        Assert.Equal(imported.Spaces[0].Id, offer.SpaceId);
        Assert.Equal([new ImportExtension(Ublock, "uBlock Origin")], offer.Extensions);
    }

    [Fact]
    public void EachArcSpaceOffersTheExtensionsOfItsOwnProfile() {
        using var arc = new BrowserDataFolder();
        arc.Write(Path.Combine("User Data", "Default", "Secure Preferences"), Settings(Extension(Ublock, "uBlock Origin")));
        arc.Write(Path.Combine("User Data", "Profile 1", "Secure Preferences"), Settings(Extension(Dark, "Dark Reader")));
        using var app = Importer();

        var imported = app.Query(new ReadImport(ImportSource.Arc, [
            new("arc", "Arc", null, ImportFixture("arc-rich", "StorableSidebar.json"), Path.Combine(arc.Path, "User Data", "Default"))
        ]));

        // "Gradient" belongs to Arc's second profile; the others to its first.
        var offered = imported.Spaces.ToDictionary(space => space.Settings.Name,
            space => imported.Extensions.Single(offer => offer.SpaceId == space.Id).Extensions.Single().ExtensionId);
        Assert.Equal(Dark, offered["Gradient"]);
        Assert.All(offered.Where(entry => entry.Key != "Gradient"), entry => Assert.Equal(Ublock, entry.Value));
        Assert.True(offered.Count > 1);
    }

    [Fact]
    public void ABrowserThatKeepsNoExtensionsOffersNone() {
        using var safari = new BrowserDataFolder();
        safari.Write(Path.Combine("Default", "Secure Preferences"), Settings(Extension(Ublock, "x")));
        using var app = Importer();

        var imported = app.Query(new ReadImport(ImportSource.Safari, [
            new("safari", "Safari", ImportFixture("safari-profile", "Bookmarks.plist"), null, Path.Combine(safari.Path, "Default"))
        ]));

        Assert.NotEmpty(imported.Spaces);
        Assert.Empty(imported.Extensions);
    }

    [Fact]
    public void TheReviewOffersEachSpacesExtensionsAndLeavesThemOnUntilTheyAreTurnedOff() {
        using var device = new TestDevice(GuardedSession(withOpenSecondSpace: false));
        var work = ImportedSpace("Work", ImportedTab("https://mail.example/"));
        var home = ImportedSpace("Home", ImportedTab("https://bank.example/"));
        var spaces = ReadSpaces(work, home);
        ImportSpaceExtensions[] offers = [
            new(spaces[0].Id, [new(Ublock, "uBlock Origin"), new(Dark, "Dark Reader")]),
            new(spaces[1].Id, [new(Ublock, "uBlock Origin"), new(Ublock, "uBlock Origin")])
        ];
        device.Send(new StartSetup(device.Workspace, SetupEntry.ImportBrowser));
        device.Send(new OfferImportSources([ImportSource.Chrome]));
        device.Send(new ToggleImportSource(ImportSource.Chrome));
        device.Send(new ContinueImport());

        var review = Flowing(device.Send(new ReviewImport(ImportSource.Chrome, spaces, [], offers))).Review!;
        // A repeat within a Space is offered once, and an extension several
        // Spaces bring installs once, into each of them.
        Assert.Equal([2, 1], review.Spaces.Select(space => space.Extensions.Count));
        Assert.Equal(3, review.IncludedExtensionCount);
        Guid Into(SetupReviewSpace space) => space.DestinationId ?? space.Source.Id;
        Assert.Equal([Ublock, Dark], review.ExtensionInstalls.Select(install => install.ExtensionId));
        Assert.Equal([Into(review.Spaces[0]), Into(review.Spaces[1])], review.ExtensionInstalls[0].SpaceIds);
        Assert.Equal([Into(review.Spaces[0])], review.ExtensionInstalls[1].SpaceIds);

        review = Flowing(device.Send(new IncludeImportExtension(spaces[0].Id, Ublock, Included: false))).Review!;
        Assert.Equal([Dark], review.Spaces[0].BroughtExtensions.Select(extension => extension.ExtensionId));
        Assert.Equal(2, review.IncludedExtensionCount);

        // An extension the Space does not offer changes nothing.
        review = Flowing(device.Send(new IncludeImportExtension(spaces[1].Id, Dark, Included: true))).Review!;
        Assert.Equal([1, 1], [review.Spaces[0].BroughtExtensions.Count, review.Spaces[1].BroughtExtensions.Count]);

        // A Space left out installs nothing, and turning it back on restores the choices.
        review = Flowing(device.Send(new IncludeImportSpace(spaces[1].Id, Included: false))).Review!;
        Assert.Equal(1, review.IncludedExtensionCount);
        review = Flowing(device.Send(new IncludeImportExtension(spaces[0].Id, Ublock, Included: true))).Review!;
        Assert.Equal([Ublock, Dark], review.Spaces[0].IncludedExtensionIds.Order());
        Assert.Equal([Ublock, Dark], review.Spaces[0].BroughtExtensions.Select(extension => extension.ExtensionId));
    }
}
