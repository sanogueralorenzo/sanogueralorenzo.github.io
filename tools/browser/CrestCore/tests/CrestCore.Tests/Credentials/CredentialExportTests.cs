using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Writing a Space's password file: its columns and quoting, the order of
/// its rows, and the file name cleaned from the Space's name.
public sealed class CredentialExportTests {
    private static readonly CrestApp Area = new();

    private static ExportedCredential Credential(string host, string username, string password, string? name = null, int port = 443,
        string note = "", Guid? id = null) =>
        new(id ?? Guid.NewGuid(), new CredentialOrigin("https", host, port), username, name, password, note);

    [Fact]
    public void EveryFieldIsQuotedAndARowWithoutANameTakesItsHost() {
        var file = Area.Query(new CredentialExport([
            Credential("accounts.crest.test", "work,person@example.com", "line one\n\"line two\"", name: "Crest, Account"),
            Credential("realm.crest.test", "ada", "secret", port: 8443, note: "HTTP Basic authentication")
        ], "Work", "Space"));

        Assert.Equal("\"name\",\"url\",\"username\",\"password\",\"note\"\r\n"
            + "\"Crest, Account\",\"https://accounts.crest.test\",\"work,person@example.com\",\"line one\n\"\"line two\"\"\",\"\"\r\n"
            + "\"realm.crest.test\",\"https://realm.crest.test:8443\",\"ada\",\"secret\",\"HTTP Basic authentication\"\r\n",
            Encoding.UTF8.GetString(file.Contents));
        Assert.Equal("Crest Passwords - Work.csv", file.FileName);
    }

    [Fact]
    public void RowsRunBySiteThenUsernameAsAPersonSortsThemThenIdentity() {
        Guid first = Guid.Parse("00000000-0000-0000-0000-000000000001"), second = Guid.Parse("00000000-0000-0000-0000-000000000002");
        var file = Area.Query(new CredentialExport([
            Credential("b.example", "user10", "s"),
            Credential("b.example", "User2", "s"),
            Credential("a.example", "zed", "s"),
            Credential("b.example", "same", "s", id: second),
            Credential("b.example", "same", "s", name: "first", id: first)
        ], "Work", "Space"));

        var rows = Encoding.UTF8.GetString(file.Contents).Split("\r\n", StringSplitOptions.RemoveEmptyEntries).Skip(1)
            .Select(row => row.Split(',')).Select(fields => (fields[0], fields[2])).ToArray();
        Assert.Equal([("\"a.example\"", "\"zed\""), ("\"first\"", "\"same\""), ("\"b.example\"", "\"same\""), ("\"b.example\"", "\"User2\""),
            ("\"b.example\"", "\"user10\"")], rows);
    }

    [Fact]
    public void TheFileNameKeepsTheSpacesLettersAndDigits() {
        Assert.Equal("Crest Passwords - Work Client.csv", CredentialExportFile.Named("Work / Client", "Space"));
        Assert.Equal("Crest Passwords - Café 東京 2.csv", CredentialExportFile.Named("  Café—東京 (2)! ", "Space"));
        Assert.Equal("Crest Passwords - Espace.csv", CredentialExportFile.Named("\U0001F512 !! ", "Espace"));
        Assert.Equal($"Crest Passwords - {new string('a', 80)}.csv", CredentialExportFile.Named(new string('a', 120), "Space"));
    }
}
