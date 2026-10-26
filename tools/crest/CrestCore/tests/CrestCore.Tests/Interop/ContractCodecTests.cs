using System.Collections;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Generator;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

/// The generated codec and the schema fingerprint. Samples are built by
/// reflection from every contract type, so a new record is covered without a
/// new test.
public sealed unsafe class ContractCodecTests {
    /// The contract types the core exports, beside its domain and application.
    private static readonly IReadOnlyList<Type> Contracts = ContractSchema.ContractTypes(typeof(Intent).Assembly);
    private static readonly Type[] Roots = [typeof(Intent), typeof(Change), typeof(Rejection), typeof(EngineCommand), typeof(EngineEvent)];
    private static readonly NullabilityInfoContext Nullability = new();

    private static bool IsQuery(Type type) {
        for (var current = type.BaseType; current is not null; current = current.BaseType)
            if (current.IsGenericType && current.GetGenericTypeDefinition() == typeof(Query<>)) return true;
        return false;
    }

    private static IEnumerable<Type> RootMembers(Type root) => Contracts
        .Where(type => type is { IsClass: true, IsAbstract: false } && (root == typeof(Query<>) ? IsQuery(type) : root.IsAssignableFrom(type)))
        .OrderBy(type => type.Name, StringComparer.Ordinal);

    /// A fixed set's members, the static instances its `All` lists, or null
    /// for any other type.
    private static IReadOnlyList<object>? SetMembers(Type type) =>
        type.IsClass && type.GetConstructors().Length == 0
            && type.GetProperty("All", BindingFlags.Public | BindingFlags.Static)?.GetValue(null) is IEnumerable members
            ? [.. members.Cast<object>()]
            : null;

    /// Every record reachable from the roots, including query answers, every
    /// fixed set the contracts declare, and every record or set they hold.
    private static IEnumerable<Type> Reachable() {
        var found = new HashSet<Type>();
        var pending = new Queue<Type>(Roots.Append(typeof(Query<>)).SelectMany(RootMembers));
        foreach (var query in RootMembers(typeof(Query<>))) pending.Enqueue(Answer(query));
        foreach (var set in Contracts.Where(type => type.IsSealed && SetMembers(type) is not null)) pending.Enqueue(set);
        while (pending.TryDequeue(out var type)) {
            if (!type.IsClass || !ContractSchema.IsContract(type) || type.IsAbstract || !found.Add(type)) continue;
            var held = SetMembers(type) is not null
                ? type.GetProperties(BindingFlags.Public | BindingFlags.Instance).Select(property => property.PropertyType)
                : type.GetConstructors().Single().GetParameters().Select(parameter => parameter.ParameterType);
            foreach (var heldType in held.Select(held => Nullable.GetUnderlyingType(held) ?? held))
                pending.Enqueue(heldType.IsGenericType ? heldType.GetGenericArguments()[0] : heldType);
        }
        return found;
    }

    private static IEnumerable<Type> Records() => Reachable().Where(type => SetMembers(type) is null);

    private static IEnumerable<Type> Sets() => Reachable().Where(type => SetMembers(type) is not null);

    private static Type Answer(Type query) {
        for (var current = query.BaseType; ; current = current!.BaseType)
            if (current!.IsGenericType && current.GetGenericTypeDefinition() == typeof(Query<>)) return current.GetGenericArguments()[0];
    }

    /// A value of `type` with every optional set or every optional absent.
    private static object Sample(Type type, NullabilityInfo? info, bool optionals) {
        if (Nullable.GetUnderlyingType(type) is { } underlying) return optionals ? Sample(underlying, null, optionals) : null!;
        if (!type.IsValueType && info?.ReadState == NullabilityState.Nullable && !optionals) return null!;
        if (type == typeof(bool)) return true;
        if (type == typeof(int)) return -7;
        if (type == typeof(long)) return 1L << 40;
        // The largest clock a hostile record can carry.
        if (type == typeof(ulong)) return ulong.MaxValue;
        if (type == typeof(double)) return -0.25;
        if (type == typeof(string)) return "Téléchargement \u202E.pdf";
        if (type == typeof(Guid)) return Guid.Parse("00112233-4455-6677-8899-aabbccddeeff");
        if (type == typeof(DateTimeOffset)) return new DateTimeOffset(2026, 9, 23, 12, 30, 15, TimeSpan.Zero);
        if (type == typeof(TimeSpan)) return TimeSpan.FromSeconds(90.5);
        if (type == typeof(byte[])) return new byte[] { 0, 0x7f, 0x80, 0xff };
        if (type.IsEnum) return Enum.GetValues(type).Cast<object>().Last();
        if (SetMembers(type) is { } members) return members[^1];
        if (Roots.Contains(type)) return Sample(RootMembers(type).First(), null, optionals);
        if (type.IsAbstract && Roots.Any(root => root.IsAssignableFrom(type)))
            return Sample(Contracts.Where(member => member is { IsAbstract: false } && type.IsAssignableFrom(member))
                .OrderBy(member => member.Name, StringComparer.Ordinal).First(), null, optionals);
        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(IReadOnlyList<>)) {
            var element = type.GetGenericArguments()[0];
            var items = Array.CreateInstance(element, 2);
            for (int index = 0; index < items.Length; index++)
                items.SetValue(Sample(element, info?.GenericTypeArguments.FirstOrDefault(), optionals), index);
            return items;
        }
        var constructor = type.GetConstructors().Single();
        return constructor.Invoke([.. constructor.GetParameters().Select(parameter =>
            Sample(parameter.ParameterType, Nullability.Create(parameter), optionals))]);
    }

    private static void AssertSameValue(object? expected, object? actual) {
        if (expected is null || actual is null) {
            Assert.Equal(expected, actual);
            return;
        }
        if (expected is not string && expected is IEnumerable sequence) {
            var expectedItems = sequence.Cast<object?>().ToList();
            var actualItems = Assert.IsAssignableFrom<IEnumerable>(actual).Cast<object?>().ToList();
            Assert.Equal(expectedItems.Count, actualItems.Count);
            for (int index = 0; index < expectedItems.Count; index++) AssertSameValue(expectedItems[index], actualItems[index]);
            return;
        }
        var type = expected.GetType();
        Assert.Equal(type, actual.GetType());
        if (SetMembers(type) is not null) {
            Assert.Same(expected, actual);
            return;
        }
        if (!ContractSchema.IsContract(type) || !type.IsClass) {
            Assert.Equal(expected, actual);
            return;
        }
        foreach (var parameter in type.GetConstructors().Single().GetParameters()) {
            var property = type.GetProperty(parameter.Name!)!;
            AssertSameValue(property.GetValue(expected), property.GetValue(actual));
        }
    }

    private static object? RoundTrip(Type type, object value) {
        var write = typeof(ContractCodec).GetMethod($"Write{type.Name}")!;
        var read = typeof(ContractCodec).GetMethod($"Read{type.Name}")!;
        var bytes = AppClient.Encode(writer => write.Invoke(null, [writer, value]));
        var reader = new WireReader(bytes);
        var decoded = read.Invoke(null, [reader]);
        reader.EnsureEnd();
        return decoded;
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void EveryContractRecordRoundTripsWithItsOptionalsSetOrAbsent(bool optionals) {
        var records = Records().ToList();
        Assert.Contains(typeof(DownloadState), records);
        foreach (var type in records) {
            var value = Sample(type, null, optionals);
            AssertSameValue(value, RoundTrip(type, value));
        }
    }

    [Fact]
    public void EachRootTagsItsTypesUniquelyInNameOrder() {
        foreach (var root in Roots.Append(typeof(Query<>))) {
            string name = root == typeof(Query<>) ? "Query" : root.Name;
            var write = typeof(ContractCodec).GetMethod($"Write{name}")!;
            var read = typeof(ContractCodec).GetMethod($"Read{name}")!;
            var tags = new List<ulong>();
            foreach (var member in RootMembers(root)) {
                var value = Sample(member, null, optionals: true);
                var bytes = AppClient.Encode(writer => write.Invoke(null, [writer, value]));
                tags.Add(new WireReader(bytes).ReadVarint());
                var reader = new WireReader(bytes);
                AssertSameValue(value, read.Invoke(null, [reader]));
                reader.EnsureEnd();
            }
            Assert.Equal(Enumerable.Range(0, tags.Count).Select(tag => (ulong)tag), tags);
        }
    }

    [Fact]
    public void EveryFixedSetMemberTravelsAsItsIndexInAll() {
        // A set only the platform's direct path to an engine carries has no
        // reader in the core's codec.
        var sets = Sets().Where(type => !type.IsDefined(typeof(OpenSetAttribute), false) &&
            typeof(ContractCodec).GetMethod($"Write{type.Name}") is not null).ToList();
        Assert.Contains(typeof(DownloadPhase), sets);
        Assert.DoesNotContain(typeof(PageExportFailure), sets);
        foreach (var type in sets) {
            var members = SetMembers(type)!;
            var write = typeof(ContractCodec).GetMethod($"Write{type.Name}")!;
            var read = typeof(ContractCodec).GetMethod($"Read{type.Name}")!;
            for (int tag = 0; tag < members.Count; tag++) {
                var bytes = AppClient.Encode(writer => write.Invoke(null, [writer, members[tag]]));
                Assert.Equal((ulong)tag, new WireReader(bytes).ReadVarint());
                var reader = new WireReader(bytes);
                Assert.Same(members[tag], read.Invoke(null, [reader]));
                reader.EnsureEnd();
            }
            var beyond = AppClient.Encode(writer => writer.WriteEnum(members.Count));
            var refused = Assert.Throws<TargetInvocationException>(() => read.Invoke(null, [new WireReader(beyond)]));
            Assert.IsType<WireFormatException>(refused.InnerException);
        }
    }

    [Fact]
    public void AFixedSetsOrderIsPartOfTheFingerprint() {
        var ordered = ContractSchema.Load([typeof(Ordered.ShowSignal)]);
        var reordered = ContractSchema.Load([typeof(Reordered.ShowSignal)]);

        Assert.Equal([("Stop", 0), ("Go", 1)], ordered.Sets.Single().Members.Select(member => (member.Name, member.Tag)));
        Assert.Equal([("Go", 0), ("Stop", 1)], reordered.Sets.Single().Members.Select(member => (member.Name, member.Tag)));
        Assert.NotEqual(ordered.Fingerprint, reordered.Fingerprint);
    }

    /// A record that holds a password, itself or through a list or an optional,
    /// names none in its Swift text: it shows each list's count and nothing
    /// else of its values, and reflects no children.
    [Fact]
    public void ARecordThatHoldsAPasswordNamesNoneInItsSwiftText() {
        string swift = SwiftEmitter.EmitContracts(ContractSchema.Load([typeof(Secret.Unlock), typeof(Secret.Remember),
            typeof(Secret.Recall), typeof(Secret.Note)]));

        foreach (string holder in new[] { "Unlock", "Remember", "Recall", "ExistingCredential" })
            Assert.Contains($"extension {holder}: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {{", swift,
                StringComparison.Ordinal);
        Assert.DoesNotContain("extension Note:", swift, StringComparison.Ordinal);
        Assert.Contains("\"Unlock(owner: <redacted>, password: <redacted>)\"", swift, StringComparison.Ordinal);
        Assert.Contains("\"Remember(credentials: \\(credentials.count), hooks: <redacted>)\"", swift, StringComparison.Ordinal);
        Assert.Contains("var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }", swift,
            StringComparison.Ordinal);
    }

    [Fact]
    public void TheAppOpensOnlyForThisBuildsSchemaFingerprint() {
        Assert.Equal(32, ContractCodec.Fingerprint.Length);
        ulong handle;
        byte[] stale = ContractCodec.Fingerprint.ToArray();
        stale[^1] ^= 1;
        Assert.Equal(CoreStatus.VersionMismatch, AppClient.Create(stale, &handle));
        Assert.Equal(0ul, handle);
        Assert.Equal(CoreStatus.VersionMismatch, AppClient.Create(ContractCodec.Fingerprint[..16], &handle));
        Assert.Equal(CoreStatus.VersionMismatch, AppClient.Create([], &handle));
        Assert.Equal(CoreStatus.Ok, AppClient.Create(ContractCodec.Fingerprint, &handle));
        Assert.NotEqual(0ul, handle);
    }

    /// The Chromium engine is built against the engine contract alone, so an
    /// edit anywhere else, or to a fixed set's data or texts, which never
    /// cross the wire, must leave its fingerprint as it was.
    [Fact]
    public void TheEngineContractKeepsItsFingerprintWhenTheApplicationContractChanges() {
        var types = Contracts;
        var schema = ContractSchema.Load(types);
        var extended = ContractSchema.Load([.. types, typeof(Ordered.ShowSignal)]);

        Assert.NotEqual(schema.Fingerprint, extended.Fingerprint);
        Assert.Equal(schema.EngineFingerprint, extended.EngineFingerprint);
        Assert.Equal(ContractCodec.EngineFingerprint.ToArray(), schema.EngineFingerprint);
        Assert.Contains("record EngineRegistration(", schema.EngineCanonical, StringComparison.Ordinal);
        Assert.Matches(@"engineevent \d+ PageClosed", schema.EngineCanonical);
        Assert.DoesNotContain("intent ", schema.EngineCanonical, StringComparison.Ordinal);
        Assert.Contains("set PageSecurity None=0 Insecure=1", schema.EngineCanonical, StringComparison.Ordinal);
        Assert.DoesNotContain("localized", schema.EngineCanonical, StringComparison.Ordinal);
        // An enum only a fixed set's data names stays out with that data.
        Assert.DoesNotContain("enum EngineMark", schema.EngineCanonical, StringComparison.Ordinal);
        // The platform's direct path to a binding shares the engine contract,
        // and the core never reads or writes it.
        Assert.Matches(@"pagerequest \d+ CapturePage -> bool", schema.EngineCanonical);
        var codec = CSharpCodecEmitter.Emit(schema);
        Assert.DoesNotContain("ReadPageRequest(", codec, StringComparison.Ordinal);
        Assert.DoesNotContain("ReadPageMediaState(", codec, StringComparison.Ordinal);
        Assert.DoesNotContain("ReadInfoBarAnswer(", codec, StringComparison.Ordinal);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void IgnoreCommand(nint context, byte* command, nuint length) { }

    [Fact]
    public void AnEngineRegistersOnlyWithThisBuildsEngineContract() {
        using var app = new AppClient();
        var registration = AppClient.Encode(writer => ContractCodec.WriteEngineRegistration(writer,
            new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true)));
        int Register(ReadOnlySpan<byte> fingerprint, out ulong engine) {
            var binding = new CrestEngineBinding { Run = &IgnoreCommand };
            CrestBuffer rejection;
            ulong handle;
            int status;
            fixed (byte* expected = fingerprint)
            fixed (byte* settings = registration)
                status = ((delegate* unmanaged[Cdecl]<ulong, byte*, nuint, byte*, nuint, CrestEngineBinding*, ulong*, CrestBuffer*, int>)
                    &Exports.EngineRegister)(app.Handle, expected, (nuint)fingerprint.Length, settings, (nuint)registration.Length, &binding,
                    &handle, &rejection);
            ((delegate* unmanaged[Cdecl]<CrestBuffer*, void>)&Exports.BufferFree)(&rejection);
            engine = handle;
            return status;
        }

        Assert.Equal(CoreStatus.VersionMismatch, Register(ContractCodec.Fingerprint, out var refused));
        Assert.Equal(0ul, refused);
        Assert.Equal(CoreStatus.Ok, Register(ContractCodec.EngineFingerprint, out var engine));
        Assert.NotEqual(0ul, engine);
        Assert.Equal(CoreStatus.Rejected, Register(ContractCodec.EngineFingerprint, out _));
    }

    [Fact]
    public void MalformedMessagesAndStaleHandlesAreStatusErrorsNotRejections() {
        var app = new AppClient();
        var acknowledge = AppClient.Encode(writer => ContractCodec.WriteIntent(writer, new AcknowledgeDownloads(Guid.NewGuid())));
        Assert.Equal(CoreStatus.Ok, app.Dispatch(acknowledge).Status);
        Assert.Equal(CoreStatus.InvalidMessage, app.Dispatch([]).Status);
        // A tag no intent has, however many intents the contract gains.
        Assert.Equal(CoreStatus.InvalidMessage, app.Dispatch([0xff, 0x7f]).Status);
        Assert.Equal(CoreStatus.InvalidMessage, app.Dispatch(acknowledge[..^1]).Status);
        Assert.Equal(CoreStatus.InvalidMessage, app.Dispatch([.. acknowledge, 0]).Status);
        Assert.Equal(CoreStatus.InvalidMessage, app.Ask([0x7f]).Status);
        Assert.Equal(CoreStatus.Ok, app.Destroy());
        Assert.Equal(CoreStatus.InvalidHandle, app.Dispatch(acknowledge).Status);
        Assert.Equal(CoreStatus.InvalidHandle, app.Destroy());
    }

    [Fact]
    public void AMessageLongerThanItsTypesLimitIsRefusedBeforeItIsRead() {
        using var app = new AppClient();
        var acknowledge = AppClient.Encode(writer => ContractCodec.WriteIntent(writer, new AcknowledgeDownloads(Guid.NewGuid())));
        var oversized = new byte[MessageLimitAttribute.DefaultBytes + 1];
        acknowledge.CopyTo(oversized);
        Assert.Equal(CoreStatus.LimitExceeded, app.Dispatch(oversized).Status);
        Assert.Equal(CoreStatus.LimitExceeded, app.Ask(oversized).Status);

        // Carrying an installed session may take as much as one stored session part.
        var installed = new byte[MessageLimitAttribute.DefaultBytes];
        AdoptLegacySession Adoption(byte[] core) => new(new LegacySession(core, null, [], null), Seed: null);
        Assert.Empty(app.Send(Adoption(installed)));
        var adoption = AppClient.Encode(writer => ContractCodec.WriteIntent(writer, Adoption(new byte[64 * 1024 * 1024])));
        Assert.Equal(CoreStatus.LimitExceeded, app.Dispatch(adoption).Status);
    }

    [Fact]
    public void TheReaderRefusesBytesNoWriterProduces() {
        Assert.Throws<WireFormatException>(() => new WireReader(new byte[] { 0x80, 0x00 }).ReadVarint());
        Assert.Throws<WireFormatException>(() => new WireReader(Enumerable.Repeat((byte)0xff, 11).ToArray()).ReadVarint());
        Assert.Throws<WireFormatException>(() => new WireReader(new byte[] { 2 }).ReadBool());
        Assert.Throws<WireFormatException>(() => new WireReader(new byte[] { 2, 0xc3, 0x28 }).ReadString());
        Assert.Throws<WireFormatException>(() => new WireReader(new byte[] { 5, 1, 2 }).ReadCount());
        Assert.Throws<WireFormatException>(() => new WireReader(new byte[] { 3, 1, 2 }).ReadBytes());
        Assert.Throws<WireFormatException>(() => new WireReader(new byte[] { 7 }).ReadEnum(7));
        Assert.Throws<WireFormatException>(() => new WireReader(BitConverter.GetBytes(double.NaN)).ReadDate());
    }
}
