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

    [Fact]
    public void CredentialQueriesAnswerThroughTheBoundary() {
        using var app = new AppClient();
        var capture = app.Ask(new CredentialCapture(Submit(Login), new(Login, Login, 1_000), null, 1_001),
            ContractCodec.ReadCredentialCaptureDecision);
        Assert.Equal(CredentialCaptureDecision.For(CredentialCaptureAction.CaptureCandidate, CredentialUsernameSource.Hint), capture);
        Assert.Equal(new InvalidCredentialOrigin(), app.Refuse(new CredentialCapture(Submit(new("ftp", "example.com", 21)), null, null, 1)));

        Guid older = Guid.NewGuid(), newer = Guid.NewGuid();
        var match = app.Ask(new CredentialSaveMatch("Person", [new(older, "person", 1, null), new(newer, "PERSON", 2, null)]),
            ContractCodec.ReadCredentialChoice);
        Assert.Equal(newer, match.CredentialId);
        Assert.Equal(new CredentialSavePlan(CredentialSavePlanKind.Update, newer),
            app.Ask(new CredentialSave(newer, new(newer, false)), ContractCodec.ReadCredentialSavePlan));
        Assert.Equal(new StaleCredentialComparison(), app.Refuse(new CredentialSave(null, new(newer, true))));
        Assert.Null(app.Ask(new MostRecentCredential([]), ContractCodec.ReadCredentialChoice).CredentialId);
        Assert.Equal(new CredentialSaveVerdict(CredentialSaveValidity.Stale),
            app.Ask(new CredentialSaveCheck(Login, Login, 1_000, 2_000), ContractCodec.ReadCredentialSaveVerdict));

        var recipe = app.Ask(new StrongPassword(null), ContractCodec.ReadStrongPasswordRecipe);
        Assert.Equal((StrongPasswordRecipe.DefaultLength, 4), (recipe.Length, recipe.Groups.Count));
        Assert.Equal(new InvalidPasswordLength(16, 64), app.Refuse(new StrongPassword(8)));
        Assert.True(app.Ask(new CredentialFill(CredentialFillSource.Generated, CredentialPasswordKind.New),
            ContractCodec.ReadCredentialFillDecision).IsAllowed);
    }

    [Fact]
    public void PasskeyAndSystemPasswordQueriesAnswerThroughTheBoundary() {
        using var app = new AppClient();
        Assert.Equal(PasskeyAccessStatus.DeviceNotConfigured, app.Ask(new PasskeyAccess(true, PasskeyDeviceConfiguration.NotConfigured,
            PasskeyAuthorizationState.Authorized), ContractCodec.ReadPasskeyAccessVerdict).Status);
        Assert.Equal(SystemPasswordWriteThroughAvailability.IsolatedLaunch,
            app.Ask(new SystemPasswordWriteThrough(true, true, true, true), ContractCodec.ReadSystemPasswordWriteThroughSupport).Availability);
        Assert.False(app.Ask(new SystemPasswordOffer(true, SystemPasswordWriteThroughAvailability.Available, true),
            ContractCodec.ReadSystemPasswordOfferDecision).Offers);
    }

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
