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

    [Fact]
    public void AFixedSetSpellsItsListsRecordsFlagsAndCountedTitlesAsSwiftLiterals() {
        var schema = ContractSchema.Load([typeof(Spelled.Key)]);
        string swift = SwiftEmitter.EmitContracts(schema);

        Assert.Equal(["Grip", "Key"], schema.Sets.Select(set => set.Name));
        Assert.Contains("static let second = Key(", swift, StringComparison.Ordinal);
        Assert.Contains("title: LocalizedStringResource(\"Press Key \\(2)\")", swift, StringComparison.Ordinal);
        Assert.Contains("title: LocalizedStringResource(\"Any Key\")", swift, StringComparison.Ordinal);
        Assert.Contains("Binding(grip: Grip.firm, modifiers: [.command, .shift])", swift, StringComparison.Ordinal);
        Assert.Contains("Binding(grip: Grip.loose, modifiers: [])", swift, StringComparison.Ordinal);
        Assert.Contains("bindings: []", swift, StringComparison.Ordinal);
        Assert.Contains("struct Binding: Equatable, Sendable {", swift, StringComparison.Ordinal);
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
    public void AnOpenSetStaysOffTheWireAndSwiftCanMakeItsMembers() {
        var schema = ContractSchema.Load([typeof(Opened.Engine)]);
        string swift = SwiftEmitter.EmitContracts(schema);

        Assert.True(schema.Sets.Single().IsOpen);
        Assert.Contains("    init(name: String, title: String) {", swift, StringComparison.Ordinal);
        Assert.Contains("static let built = Engine(name: \"built\", title: \"Built In\")", swift, StringComparison.Ordinal);
        Assert.Contains("lhs.name == rhs.name", swift, StringComparison.Ordinal);
        Assert.Contains("static let madePrefix = \"made:\"", swift, StringComparison.Ordinal);
        Assert.DoesNotContain("tag", swift, StringComparison.Ordinal);
        Assert.DoesNotContain("extension Engine {", SwiftEmitter.EmitCodec(schema), StringComparison.Ordinal);
        Assert.DoesNotContain("ReadEngine(", CSharpCodecEmitter.Emit(schema), StringComparison.Ordinal);
    }

    /// A field typed as an abstract intent holds only the intents that derive
    /// from it, travelling with their intent tags, so each side refuses any
    /// other intent where the field is read.
    [Fact]
    public void AFieldTypedAsAUnionBaseHoldsOnlyItsMembersUnderTheirRootTags() {
        var schema = ContractSchema.Load([typeof(Narrowed.Slide), typeof(Narrowed.Jump), typeof(Narrowed.Resign), typeof(Narrowed.MoveCheck)]);
        string codec = CSharpCodecEmitter.Emit(schema);
        string swift = SwiftEmitter.EmitContracts(schema);
        string swiftCodec = SwiftEmitter.EmitCodec(schema);

        Assert.Contains("record MoveCheck(Move: union:Intent/Move)", schema.Canonical, StringComparison.Ordinal);
        Assert.Contains("base Move of intent Jump Slide\n", schema.Canonical, StringComparison.Ordinal);
        Assert.Contains("case 0: return ReadJump(reader);", codec, StringComparison.Ordinal);
        Assert.Contains("case 2: return ReadSlide(reader);", codec, StringComparison.Ordinal);
        Assert.Contains("Intent tag {tag} is not a Move.", codec, StringComparison.Ordinal);
        Assert.Contains("public static void WriteMove(WireWriter writer, Move value) => WriteIntent(writer, value);", codec,
            StringComparison.Ordinal);
        Assert.Contains("protocol Move: Intent {}", swift, StringComparison.Ordinal);
        Assert.Contains("struct Slide: Intent, Move, Equatable, Sendable {", swift, StringComparison.Ordinal);
        Assert.Contains("struct Resign: Intent, Equatable, Sendable {", swift, StringComparison.Ordinal);
        Assert.Contains("    let move: any Move\n", swift, StringComparison.Ordinal);
        Assert.Contains("static func decodeMove(from reader: inout WireReader) throws(WireError) -> any Move {", swiftCodec,
            StringComparison.Ordinal);
        Assert.Contains("move.encodeIntent(into: &writer)", swiftCodec, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(typeof(Opened.SendEngine), "SendEngine.Value:")]
    [InlineData(typeof(Malformed.SendUnlisted), "Unlisted.Hidden:")]
    [InlineData(typeof(Malformed.SendConstructible), "Constructible:")]
    [InlineData(typeof(Malformed.SendDated), "Dated.When:")]
    [InlineData(typeof(Malformed.SendStamped), "Stamp.Id:")]
    [InlineData(typeof(Malformed.SendUncounted), "Uncounted.Title:")]
    public void TheGeneratorRefusesAFixedSetItCannotTagOrSpell(Type intent, string culprit) {
        var error = Assert.Throws<ContractSchemaException>(() => ContractSchema.Load([intent]));
        Assert.StartsWith(culprit, error.Message, StringComparison.Ordinal);
    }

    /// An observed record reaches Swift as a model that keeps each field in
    /// storage Observation ignores and whose `update` stores a field that
    /// differs before it announces the change, so a view rendered during the
    /// announcement reads the new value and an equal field notifies no one;
    /// the wire and its fingerprint stay as they were.
    [Fact]
    public void AnObservedRecordBecomesAModelThatStoresEachChangedFieldBeforeAnnouncingIt() {
        var schema = ContractSchema.Load([typeof(Watched.Lamp), typeof(Watched.Dimmer)]);
        string swift = SwiftEmitter.EmitContracts(schema);

        Assert.Contains("@MainActor\n@Observable\nfinal class LampModel: ObservedModel, Identifiable {\n    let id: UUID\n"
            + "    var label: String {\n        access(keyPath: \\.label)\n        return labelStorage\n    }\n"
            + "    var isLit: Bool? {\n        access(keyPath: \\.isLit)\n        return isLitStorage\n    }\n",
            swift, StringComparison.Ordinal);
        Assert.Contains("    @ObservationIgnored private var labelStorage: String\n    @ObservationIgnored private var isLitStorage: Bool?\n"
            + "    @ObservationIgnored private var levelsStorage: [Int]\n", swift, StringComparison.Ordinal);
        Assert.Contains("        Lamp(id: id, label: label, isLit: isLit, levels: levels)\n", swift, StringComparison.Ordinal);
        Assert.Contains("    init(_ value: Lamp) {\n        id = value.id\n        labelStorage = value.label\n", swift, StringComparison.Ordinal);
        Assert.Contains("    func update(_ value: Lamp) {\n        precondition(value.id == id, ", swift, StringComparison.Ordinal);
        Assert.Contains("        if labelStorage != value.label {\n            labelStorage = value.label\n"
            + "            withMutation(keyPath: \\.label) {}\n        }\n", swift, StringComparison.Ordinal);
        Assert.DoesNotContain("idStorage", swift, StringComparison.Ordinal);
        Assert.Contains("final class DimmerModel: ObservedModel {\n    var level: Double {\n", swift, StringComparison.Ordinal);
        Assert.Contains("        if levelStorage != value.level {\n            levelStorage = value.level\n"
            + "            withMutation(keyPath: \\.level) {}\n        }\n", swift, StringComparison.Ordinal);
        Assert.Equal(ContractSchema.Load([typeof(Unwatched.Lamp), typeof(Unwatched.Dimmer)]).Fingerprint, schema.Fingerprint);
    }

    /// A record the core resolves values of reaches Swift with a seed where a
    /// message the platform sends holds it: its fields alone, with seeds in
    /// them, which the message holds and encodes, so no platform works out a
    /// resolved value. The core reads a seed's fields alone and still writes
    /// the record whole. A record only the core writes has no seed, and a
    /// message the platform sends resolves nothing of its own.
    [Fact]
    public void ARecordASentMessageHoldsReachesSwiftAsAFieldsOnlySeed() {
        var schema = ContractSchema.Load([typeof(Seeded.KeepTab)]);
        string swift = SwiftEmitter.EmitContracts(schema);
        string codec = SwiftEmitter.EmitCodec(schema);
        string core = CSharpCodecEmitter.Emit(schema);

        Assert.Contains("struct KeepTab: Intent, Equatable, Sendable {\n    let archived: ArchivedTabState.Seed\n}\n", swift, StringComparison.Ordinal);
        Assert.Contains("    struct Seed: Equatable, Sendable {\n        var tab: TabState.Seed\n        var archivedAt: Date\n"
            + "        var reason: ArchiveReason\n    }\n", swift, StringComparison.Ordinal);
        Assert.Contains("    var seed: Seed {\n        Seed(tab: tab.seed, archivedAt: archivedAt, reason: reason)\n    }\n", swift,
            StringComparison.Ordinal);
        string tabSeed = codec[codec.IndexOf("extension TabState.Seed {", StringComparison.Ordinal)..];
        tabSeed = tabSeed[..tabSeed.IndexOf("\n}\n", StringComparison.Ordinal)];
        Assert.Contains("keepsPageLoaded", tabSeed, StringComparison.Ordinal);
        Assert.DoesNotContain("displayTitle", tabSeed, StringComparison.Ordinal);
        Assert.Contains("let archived = try ArchivedTabState.Seed(from: &reader)", codec, StringComparison.Ordinal);
        Assert.Contains("            ReadArchivedTabStateSeed(reader));", core, StringComparison.Ordinal);
        string readSeed = core[core.IndexOf("public static TabState ReadTabStateSeed(", StringComparison.Ordinal)..];
        Assert.DoesNotContain("_ = ", readSeed[..readSeed.IndexOf("\n    }\n", StringComparison.Ordinal)], StringComparison.Ordinal);
        Assert.Contains("public static TabState ReadTabState(WireReader reader)", core, StringComparison.Ordinal);

        Assert.DoesNotContain("struct Seed", SwiftEmitter.EmitContracts(ContractSchema.Load([typeof(Seeded.TabKept)])),
            StringComparison.Ordinal);
        var error = Assert.Throws<ContractSchemaException>(() => ContractSchema.Load([typeof(Seeded.Resolving)]));
        Assert.StartsWith("Resolving:", error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(typeof(Unwatchable.Valued), "Valued.Value:")]
    [InlineData(typeof(Unwatchable.Numbered), "Numbered.Id:")]
    [InlineData(typeof(Unwatchable.Unreached), "Unreached:")]
    public void TheGeneratorRefusesAnObservedRecordItCannotModel(Type type, string culprit) {
        var error = Assert.Throws<ContractSchemaException>(() => ContractSchema.Load([type]));
        Assert.StartsWith(culprit, error.Message, StringComparison.Ordinal);
    }

    /// A record normalized on construction reaches Swift as `Hashable` with
    /// only a labeled wire initializer, which the codec calls, so the natural
    /// spelling is left to the platform's normalizing initializer; the wire and
    /// its fingerprint stay as they were.
    [Fact]
    public void ANormalizedRecordReachesSwiftWithOnlyItsWireInitializer() {
        var schema = ContractSchema.Load([typeof(Normalized.Badge)]);
        string swift = SwiftEmitter.EmitContracts(schema);

        Assert.Contains("struct Badge: CoreChange, Hashable, Sendable {\n    let name: String\n    let rank: Int\n", swift, StringComparison.Ordinal);
        Assert.Contains("    init(normalized name: String, rank: Int) {\n        self.name = name\n        self.rank = rank\n    }\n",
            swift, StringComparison.Ordinal);
        Assert.Contains("        self.init(normalized: name, rank: rank)\n", SwiftEmitter.EmitCodec(schema), StringComparison.Ordinal);
        Assert.Equal(ContractSchema.Load([typeof(Unnormalized.Badge)]).Fingerprint, schema.Fingerprint);
    }

    /// A record's public constants and static values reach Swift as static
    /// literals at the top of its struct, a record spelled with its resolved
    /// values as the core computed them; they never cross the wire.
    [Fact]
    public void ARecordsStaticsReachSwiftAsLiteralsAndStayOffTheWire() {
        var schema = ContractSchema.Load([typeof(Statics.Gauge)]);
        string swift = SwiftEmitter.EmitContracts(schema);

        Assert.Contains("struct Gauge: CoreChange, Equatable, Sendable {\n    static let limit: Int = 3\n    static let full: Double = 100\n"
            + "    static let empty = Gauge(label: \"\", level: 0, tint: nil, share: 0)\n"
            + "    static let tinted = Gauge(label: \"tinted\", level: 25, tint: BrandColor(red: 0.5, green: 0.25, blue: 0.125, alpha: 1), share: 0.25)\n\n"
            + "    let label: String\n", swift, StringComparison.Ordinal);
        Assert.Equal(ContractSchema.Load([typeof(Unstatic.Gauge)]).Fingerprint, schema.Fingerprint);
    }

    [Theory]
    [InlineData(typeof(Unspellable.Stamped), "Stamped.Nobody:")]
    [InlineData(typeof(Unspellable.Settable), "Settable.Current:")]
    public void TheGeneratorRefusesAPublicStaticSwiftCannotSpell(Type type, string culprit) {
        var error = Assert.Throws<ContractSchemaException>(() => ContractSchema.Load([type]));
        Assert.StartsWith(culprit, error.Message, StringComparison.Ordinal);
    }

    /// Only the generated codec may call a wire initializer: a value made
    /// through one anywhere else was never normalized.
    [Fact]
    public void TheGeneratorFindsEveryWireInitializerCallOutsideTheCodec() {
        var schema = ContractSchema.Load([typeof(Normalized.Badge)]);
        var calls = SwiftEmitter.WireInitializerCalls(schema, [
            ("Made.swift", "let badge = Badge(name: \"Gold\", rank: 1)\n// Badge(normalized: \"gold\", rank: 1)\n"),
            ("Called.swift", "let a = Badge(normalized: \"gold\", rank: 1)\nlet b = Badge.init(\n    normalized: \"gold\", rank: 2)\n"
                + "let c: Badge = .init(normalized: \"gold\", rank: 3)\n")
        ]);

        Assert.Equal(["Called.swift:1:", "Called.swift:2:", "Called.swift:4:"], calls.Select(call => call.Split(' ')[0]));
        Assert.Contains("make the value with Badge(name:rank:), which normalizes.", calls[0], StringComparison.Ordinal);
    }

    /// A view that reads a read-model object's whole record observes every
    /// field, so any change redraws it. The generator finds such reads in view
    /// sources, through the names and members the sources type as read-model
    /// objects, and leaves other sources and other `value`s alone.
    [Fact]
    public void TheGeneratorFindsEveryWholeRecordReadInAView() {
        var schema = ContractSchema.Load([typeof(Watched.Lamp), typeof(Watched.Dimmer)]);
        (string, string)[] sources = [
            ("App/ReadModel/Room.swift", "final class RoomModel: ObservedModel, Identifiable {\n    let lamps: ObservedList<LampModel>\n"
                + "    var dimmers: [UUID: DimmerModel] = [:]\n    var value: Room { Room(lamps: lamps.values) }\n}\n"),
            ("App/Features/Lamps/LampRow.swift", "struct LampRow: View {\n    let lamp: LampModel\n    let room: RoomModel\n"
                + "    var body: some View {\n        Text(lamp.label)\n        Text(\"\\(lamp.value)\")\n"
                + "        ForEach(room.lamps.values) { _ in }\n        _ = room.lamps.model(id)?.value\n"
                + "        _ = room.dimmers[id]?.value\n        _ = room.lamps.models.map(\\.value)\n        _ = room?.value\n"
                + "        // lamp.value\n        _ = slider.value\n    }\n}\n"),
            ("App/Application/LampStore.swift", "let lamp: LampModel\n_ = lamp.value\n")
        ];

        var reads = SwiftEmitter.WholeRecordReads(schema, sources);

        Assert.Equal(["App/Features/Lamps/LampRow.swift:6:", "App/Features/Lamps/LampRow.swift:7:", "App/Features/Lamps/LampRow.swift:8:",
            "App/Features/Lamps/LampRow.swift:9:", "App/Features/Lamps/LampRow.swift:10:", "App/Features/Lamps/LampRow.swift:11:"],
            reads.Select(read => read.Split(' ')[0]));
        Assert.Contains("(lamp.value)", reads[0], StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(typeof(Unnormalizable.Blank), "Blank:")]
    [InlineData(typeof(Unnormalizable.Tinted), "Tinted.Hues:")]
    public void TheGeneratorRefusesANormalizedRecordSwiftCannotHash(Type type, string culprit) {
        var error = Assert.Throws<ContractSchemaException>(() => ContractSchema.Load([type]));
        Assert.StartsWith(culprit, error.Message, StringComparison.Ordinal);
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
