using CrestCore.Contracts;
using CrestCore.Domain;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

/// The credentials area through the native app boundary: encoded queries in,
/// encoded answers or one rejection out, and no password on either side.
public sealed class AppCredentialTests {
    private static readonly CredentialOrigin Login = new("https", "accounts.example.com", 443);

    private static CredentialFormFacts Submit(CredentialOrigin frame) =>
        new(CredentialCaptureEvent.Submit, frame, Login, true, true, false, true, CredentialPasswordKind.Current, null, true);

    /// Passwords never cross the boundary: the only text a credential question
    /// carries is an origin and, where accounts are matched, a username.
    [Fact]
    public void NoCredentialQueryCarriesAPassword() {
        Type[] queries = [typeof(CredentialCapture), typeof(CredentialFill), typeof(CredentialSaveCheck), typeof(MostRecentCredential),
            typeof(CredentialSaveMatch), typeof(CredentialSave), typeof(StrongPassword)];
        var found = new HashSet<Type>();
        var pending = new Queue<Type>(queries);
        var text = new SortedSet<string>(StringComparer.Ordinal);
        while (pending.TryDequeue(out var type)) {
            // A fixed set travels as its index in `All`, so it carries no text.
            if (!found.Add(type) || type.GetProperty("All") is not null) continue;
            foreach (var parameter in type.GetConstructors().Single().GetParameters()) {
                var parameterType = Nullable.GetUnderlyingType(parameter.ParameterType) ?? parameter.ParameterType;
                if (parameterType.IsGenericType) parameterType = parameterType.GetGenericArguments()[0];
                if (parameterType == typeof(string)) text.Add($"{type.Name}.{parameter.Name}");
                else if (parameterType.IsClass && parameterType.Assembly == typeof(Query<>).Assembly) pending.Enqueue(parameterType);
            }
        }
        Assert.Equal(["CredentialOrigin.Host", "CredentialOrigin.Scheme", "CredentialRecord.Username", "CredentialSaveMatch.Username"], text);
    }
}
