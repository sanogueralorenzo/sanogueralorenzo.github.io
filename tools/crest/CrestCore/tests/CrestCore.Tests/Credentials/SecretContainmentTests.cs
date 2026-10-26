using System.Reflection;
using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The core keeps no password: no record that holds one is reachable from a
/// change, an intent, the session it stores, the device store or the sync
/// journal, and none names a secret in its text form.
public sealed class SecretContainmentTests {
    private const string Secret = "correct-horse-battery-staple";

    private static readonly Assembly Core = typeof(CrestApp).Assembly;

    /// Every record marked as holding secrets.
    private static IReadOnlyList<Type> SecretTypes => [.. Core.GetTypes()
        .Where(type => type.IsDefined(typeof(HoldsSecretsAttribute), inherit: false))];

    [Fact]
    public void NoRecordThatHoldsAPasswordIsReachableFromWhatTheCoreKeepsOrPublishes() {
        Assert.Contains(typeof(CredentialImportPlan), SecretTypes);
        Assert.Contains(typeof(ExistingCredential), SecretTypes);
        var types = Core.GetTypes();
        var roots = types.Where(type => !type.IsAbstract && (typeof(Change).IsAssignableFrom(type) || typeof(Intent).IsAssignableFrom(type)))
            .Concat([typeof(SessionState), typeof(StoredSession), typeof(FirstSession), typeof(DeviceRecords), typeof(NativeSyncJournal),
                typeof(NativeSyncSessionTransition)]);
        var secrets = SecretTypes.ToHashSet();
        var reached = new HashSet<Type>();
        var pending = new Stack<(Type Type, string Path)>(roots.Select(root => (root, root.Name)));
        while (pending.TryPop(out var next)) {
            var (type, path) = next;
            if (!reached.Add(type)) continue;
            Assert.False(secrets.Contains(type), $"{path} reaches {type.Name}, which holds passwords.");
            foreach (var reference in References(type, types)) pending.Push((reference, $"{path} → {reference.Name}"));
        }
        Assert.Contains(typeof(SessionState), reached);
    }

    [Fact]
    public void NoRecordThatHoldsAPasswordNamesItInItsText() {
        var origin = new CredentialOrigin("https", "accounts.example", 443);
        var candidate = new CredentialImportCandidate(2, Secret, Secret, Secret, CredentialImportEffect.Adds);
        var group = new CredentialImportGroup(origin, Secret, [candidate], 0, null, 2);
        object[] records = [
            new ImportedCredential(2, Secret, origin, Secret, Secret),
            new ExistingCredential(Guid.NewGuid(), origin, Secret, true, 1, null, Secret),
            candidate,
            group,
            new CredentialImportPlan(CredentialFileFormat.Browser, [group], [], []),
            new CredentialImportPreview(Encoding.UTF8.GetBytes(Secret), []),
            new PasswordImportPreview([new(2, null, origin, Secret, Secret)], []),
            new ExportedCredential(Guid.NewGuid(), origin, Secret, Secret, Secret, Secret),
            new CredentialExport([new(Guid.NewGuid(), origin, Secret, null, Secret, "")], "Work", "Space"),
            new CredentialExportFile("Crest Passwords - Work.csv", Encoding.UTF8.GetBytes(Secret)),
            CredentialFile.Read(Encoding.UTF8.GetBytes($"url,username,password\nhttps://accounts.example,{Secret},{Secret}"))
        ];
        Assert.Equal(SecretTypes.ToHashSet(), records.Select(record => record.GetType()).ToHashSet());
        foreach (var record in records) {
            Assert.DoesNotContain(Secret, record.ToString(), StringComparison.Ordinal);
            Assert.DoesNotContain(Secret, $"{record}", StringComparison.Ordinal);
        }
    }

    /// The types a value of `type` can hold: its fields' and properties'
    /// types, their element and argument types, and for an abstract type,
    /// every type of the core that derives from it.
    private static IEnumerable<Type> References(Type type, Type[] types) {
        if (type.IsArray) return [type.GetElementType()!];
        var held = new List<Type>();
        if (type.IsGenericType) held.AddRange(type.GetGenericArguments());
        if (type.Namespace?.StartsWith("System", StringComparison.Ordinal) == true || type.IsPrimitive || type.IsEnum) return held;
        if (type.IsAbstract || type.IsInterface)
            held.AddRange(types.Where(derived => derived != type && !derived.IsAbstract && type.IsAssignableFrom(derived)));
        const BindingFlags members = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        held.AddRange(type.GetFields(members).Select(field => field.FieldType));
        held.AddRange(type.GetProperties(members).Select(property => property.PropertyType));
        return held;
    }
}
