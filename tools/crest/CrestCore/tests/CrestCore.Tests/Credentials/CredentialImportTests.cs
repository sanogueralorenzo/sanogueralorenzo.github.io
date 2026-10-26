using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Reading a password file for an import: its limits, its encoding, the
/// headers each browser and password manager writes, the rows it leaves out
/// or warns about, and what each account means against the passwords the
/// Space keeps.
public sealed class CredentialImportTests {
    private static readonly CrestApp Area = new();
    private static readonly CredentialOrigin Accounts = new("https", "accounts.example", 443);

    private static CredentialImportPlan Preview(string text, params ExistingCredential[] existing) =>
        Area.Query(new CredentialImportPreview(Encoding.UTF8.GetBytes(text), existing));

    private static CredentialFileFlaw Flaw(byte[] document) =>
        Assert.IsType<InvalidCredentialFile>(Assert.Throws<Rejected>(() =>
            Area.Query(new CredentialImportPreview(document, []))).Rejection).Flaw;

    private static CredentialFileFlaw Flaw(string text) => Flaw(Encoding.UTF8.GetBytes(text));

    private static ExistingCredential Saved(string username, string password, double updatedAt = 1_000, double? lastUsedAt = null,
        bool isWebForm = true, CredentialOrigin? origin = null) =>
        new(Guid.NewGuid(), origin ?? Accounts, username, isWebForm, updatedAt, lastUsedAt, password);

    [Fact]
    public void EachBrowsersHeadersNameTheColumnsAndTheFormat() {
        var browser = Preview("name,url,username,password,note\nWork,https://accounts.example/login,ada,secret,\n");
        Assert.Equal((CredentialFileFormat.Browser, "Work"), (browser.Format, browser.Groups[0].Candidates[0].DisplayName));
        Assert.Equal(CredentialFileFormat.Firefox, Preview(
            "\"url\",\"username\",\"password\",\"httpRealm\",\"formActionOrigin\",\"guid\"\n\"https://accounts.example\",\"ada\",\"s\",,,\"{1}\"\n")
            .Format);
        Assert.Equal(CredentialFileFormat.Safari, Preview("Title,URL,Username,Password,Notes,OTPAuth\nWork,https://accounts.example,ada,s,,\n")
            .Format);
        var bitwarden = Preview(
            "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n,,login,Work,,,0,https://accounts.example,ada,s,\n");
        Assert.Equal((CredentialFileFormat.Bitwarden, "ada"), (bitwarden.Format, bitwarden.Groups[0].Username));

        Assert.Equal(CredentialFileFlaw.SeveralSiteColumns, Flaw("url,origin,username,password\nhttps://one.example,https://two.example,u,s"));
        Assert.Equal(CredentialFileFlaw.SeveralPasswordColumns, Flaw("url,username,password,pass\nhttps://one.example,u,s,t"));
        Assert.Equal(CredentialFileFlaw.NoPasswordColumn, Flaw("url,username\nhttps://one.example,user"));
        Assert.Equal(CredentialFileFlaw.NoSiteColumn, Flaw("username,password\nuser,secret"));
        Assert.Equal(CredentialFileFlaw.Malformed, Flaw("url,username,password\n\"https://one.example,user,secret"));
        Assert.Equal(CredentialFileFlaw.Malformed, Flaw("url,username,password\nhttps://one.example,us\"er,secret"));
    }

    [Fact]
    public void BrokenRowsAreLeftOutAndPlainHttpRowsWarnWithoutLosingValidRows() {
        var plan = Preview("""
            url,username,password
            https://valid.example/path,,valid-secret

            http://insecure.example,user,insecure-secret
            not a url,user,bad-secret
            https://empty.example,user,
            https://wide.example,user,secret,extra
            accounts.example,bare,secret
            """);
        // Blank rows are skipped before rows are numbered.
        Assert.Equal([2, 3, 7], plan.Groups.SelectMany(group => group.Candidates).Select(candidate => candidate.RowNumber).Order());
        Assert.Equal([new(4, CredentialRowFlaw.InvalidOrigin), new(5, CredentialRowFlaw.EmptyPassword), new(6, CredentialRowFlaw.MalformedRow)],
            plan.Rejections);
        Assert.Equal([new CredentialRowWarning(3, CredentialRowCaution.InsecureOrigin)], plan.Warnings);
        // A site without a scheme is HTTPS; an origin keeps a port only when it is not the default.
        Assert.Contains(plan.Groups, group => group.Origin == new CredentialOrigin("https", "accounts.example", 443));
        Assert.Equal(new CredentialOrigin("http", "xn--bcher-kva.example", 8080),
            Preview("url,username,password\nHTTP://Bücher.Example:08080/login,u,s").Groups[0].Origin);
    }

    [Fact]
    public void ABracketedHostMustBeAnIPv6AddressWithoutAZoneId() {
        var plan = Preview("""
            url,username,password
            https://[2001:DB8::1]:8443/,u,s
            https://[a b]/,u,s
            https://[a%2Fb]/,u,s
            https://[%5B::1%5D]/,u,s
            https://[1.2.3.4]/,u,s
            https://[v1.x]/,u,s
            https://[:::]/,u,s
            https://[fe80::1%25en0]/,u,s
            https://[fe80::1%41]/,u,s
            """);
        Assert.Equal(new CredentialOrigin("https", "2001:db8::1", 8443), Assert.Single(plan.Groups).Origin);
        Assert.Equal(Enumerable.Range(3, 8).Select(row => new CredentialRowRejection(row, CredentialRowFlaw.InvalidOrigin)), plan.Rejections);
        // A page never reports a zone ID, so a saved password cannot hold one either.
        Assert.False(new CredentialOrigin("https", "fe80::1%en0", 443).IsValid);
    }

    [Fact]
    public void AnIPAddressIsSpelledAsAPageReportsItSoThePasswordFillsAndMerges() {
        var saved = Saved("ada", "secret", origin: new("https", "127.0.0.1", 443));
        var plan = Preview("""
            url,username,password
            https://127.1/,ada,secret
            https://0x7f.0.0.1./,bob,secret
            https://[2001:db8:0:0:0:0:0:1]/,ada,secret
            https://[::ffff:1.2.3.4]/,ada,secret
            https://999.1.1.1/,ada,secret
            https://1.2.3.4.5/,ada,secret
            https://08.1.1.1/,ada,secret
            https://[::ffff:1.2.3.04]/,ada,secret
            """, saved);
        Assert.Equal([("127.0.0.1", "ada"), ("127.0.0.1", "bob"), ("2001:db8::1", "ada"), ("::ffff:102:304", "ada")],
            plan.Groups.Select(group => (group.Origin.Host, group.Username)));
        Assert.Equal(saved.Id, plan.Groups[0].ExistingId);
        // A host ending in a number must be an IPv4 address, and an IPv6 address
        // must spell any IPv4 address it ends in without leading zeros, or no
        // page can have it.
        Assert.Equal(Enumerable.Range(6, 4).Select(row => new CredentialRowRejection(row, CredentialRowFlaw.InvalidOrigin)), plan.Rejections);
        Assert.False(new CredentialOrigin("https", "2001:db8:0:0:0:0:0:1", 443).IsValid);
        Assert.False(new CredentialOrigin("https", "127.1", 443).IsValid);
    }

    [Fact]
    public void AnAccountsRowsGroupAgainstItsMostRecentSavedPassword() {
        var older = Saved("ADA", "old-secret", updatedAt: 3_000);
        var newer = Saved("ada", "current-secret", updatedAt: 1_000, lastUsedAt: 5_000);
        var httpAuth = Saved("grace", "realm-secret", isWebForm: false);
        var plan = Preview("""
            url,username,password
            https://accounts.example,Ada,current-secret
            https://accounts.example,ada,new-secret
            https://accounts.example,ADA,current-secret
            https://accounts.example,grace,grace-secret
            https://zeta.example,bob,bob-secret
            https://accounts.example,alan,alan-secret
            """, older, newer, httpAuth);

        Assert.Equal([("accounts.example", "Ada"), ("accounts.example", "alan"), ("accounts.example", "grace"), ("zeta.example", "bob")],
            plan.Groups.Select(group => (group.Origin.Host, group.Username)));
        var ada = plan.Groups[0];
        Assert.Equal((newer.Id, (int?)null, 1, true), (ada.ExistingId, ada.SuggestedRow, ada.CollapsedDuplicateRowCount, ada.RequiresChoice));
        Assert.Equal([(2, CredentialImportEffect.Matches), (3, CredentialImportEffect.Replaces)],
            ada.Candidates.Select(candidate => (candidate.RowNumber, candidate.Effect)));
        // Only a web form's password stands for an account a file imports.
        var grace = plan.Groups[2];
        Assert.Equal((null, (int?)5, false, CredentialImportEffect.Adds),
            (grace.ExistingId, grace.SuggestedRow, grace.RequiresChoice, grace.Candidates[0].Effect));
        Assert.Equal(6, plan.ValidRowCount);

        // A file that repeats the saved password needs no choice.
        var same = Preview("url,username,password\nhttps://accounts.example,ada,current-secret", newer).Groups[0];
        Assert.Equal((false, CredentialImportEffect.Matches), (same.RequiresChoice, same.Candidates[0].Effect));
    }
}
