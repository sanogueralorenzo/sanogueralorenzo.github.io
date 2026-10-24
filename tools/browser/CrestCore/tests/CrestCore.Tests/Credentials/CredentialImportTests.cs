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
    public void AFileOverAnyLimitIsRefusedWhole() {
        Assert.Equal(CredentialFileFlaw.TooLarge, Flaw(new byte[CredentialFile.MaximumBytes + 1]));

        string rows = string.Concat(Enumerable.Range(0, CredentialFile.MaximumRows).Select(index => $"https://site{index}.example,u,p\n"));
        Assert.Equal(CredentialFile.MaximumRows, Preview("url,username,password\n" + rows).ValidRowCount);
        Assert.Equal(CredentialFileFlaw.TooManyRows, Flaw("url,username,password\n" + rows + "https://one.more.example,u,p\n"));

        string columns = string.Join(',', Enumerable.Range(0, CredentialFile.MaximumColumns - 3).Select(index => $"extra{index}"));
        Assert.Single(Preview($"url,username,password,{columns}\nhttps://one.example,u,p\n").Groups);
        Assert.Equal(CredentialFileFlaw.TooManyColumns, Flaw($"url,username,password,{columns},one_more\nhttps://one.example,u,p\n"));

        string field = new('x', CredentialFile.MaximumFieldCharacters);
        Assert.Single(Preview($"url,username,password\nhttps://one.example,u,{field}\n").Groups);
        Assert.Equal(CredentialFileFlaw.FieldTooLarge, Flaw($"url,username,password\nhttps://one.example,u,\"{field}x\"\n"));
    }

    [Fact]
    public void OnlyUtf8TextWithAHeaderAndARowImports() {
        Assert.Equal(CredentialFileFlaw.NotText, Flaw([0x75, 0x72, 0x6c, 0xff, 0xfe]));
        Assert.Equal(CredentialFileFlaw.Empty, Flaw([]));
        Assert.Equal(CredentialFileFlaw.Empty, Flaw(" , \n\r\n , "));
        Assert.Equal(CredentialFileFlaw.NoRows, Flaw("url,username,password\n\n"));
        // A byte-order mark and CRLF line breaks read as any other file does.
        var plan = Preview("\uFEFFURL,Username,Password\r\nhttps://accounts.example,ada,\"line one\r\nline two\"\r\n");
        Assert.Equal(("ada", "line one\nline two"), (plan.Groups[0].Username, plan.Groups[0].Candidates[0].Password));
    }

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

    [Fact]
    public void AnotherBrowsersPasswordsImportAsABrowsersOwnFileWould() {
        var plan = Area.Query(new PasswordImportPreview([
            new(2, "accounts.example", Accounts, "ada", "secret"),
            new(3, null, new CredentialOrigin("ftp", "files.example", 21), "ada", "secret"),
            new(4, null, Accounts, "grace", "")
        ], [Saved("ada", "secret")]));
        Assert.Equal(CredentialFileFormat.Browser, plan.Format);
        Assert.Equal([new(3, CredentialRowFlaw.InvalidOrigin), new(4, CredentialRowFlaw.EmptyPassword)], plan.Rejections);
        Assert.Equal(CredentialImportEffect.Matches, Assert.Single(plan.Groups).Candidates[0].Effect);
    }
}
