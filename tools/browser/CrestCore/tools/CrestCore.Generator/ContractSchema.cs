using System.Globalization;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

using CrestCore.Contracts;

namespace CrestCore.Generator;

/// The kinds of contract message. Each root's concrete types form a union
/// whose wire tag is the type's index in ordinal name order.
///
/// A root travels one way. The core reads what travels to it (intents,
/// queries, engine events and engine questions), so each of those is a message
/// on its own with a byte limit. The core writes changes, rejections and engine commands. A
/// platform encodes what it sends through a protocol and decodes what it
/// receives as the cases of one enum. The engine roots form the engine
/// contract, which an engine binding checks by its own fingerprint; two of
/// them never reach the core, because they carry the platform's direct path to
/// a binding (`EnginePage`): the requests it makes of a page's engine and what
/// the binding presents back.
internal sealed class ContractRoot {
    #region Variables

    public static readonly ContractRoot Intent = new(typeof(Intent), travelsToCore: true,
        swiftDocumentation: "A request to change the core's state, sent with `CrestCore.send`.");
    public static readonly ContractRoot Change = new(typeof(Change), travelsToCore: false,
        swiftDocumentation: "Everything an intent can change. `CoreState.apply` keeps the read model current.");
    public static readonly ContractRoot Rejection = new(typeof(Rejection), travelsToCore: false,
        swiftDocumentation: "The rule that refused an intent or a query.", swiftConformances: "Error, Sendable");
    public static readonly ContractRoot Query = new(typeof(Query<>), travelsToCore: true,
        swiftDocumentation: "A question the core answers without changing state, asked with `CrestCore.query`.");
    public static readonly ContractRoot EngineCommand = new(typeof(EngineCommand), travelsToCore: false, isEngine: true,
        swiftDocumentation: "What the core asks an engine binding to do, run by `EngineBinding.run`.");
    public static readonly ContractRoot EngineEvent = new(typeof(EngineEvent), travelsToCore: true, isEngine: true,
        swiftDocumentation: "What happened to one of an engine binding's pages, reported with `CrestCore.report`.");
    public static readonly ContractRoot PageRequest = new(typeof(PageRequest<>), travelsToCore: false, isEngine: true,
        reachesCore: false, platformSends: true,
        swiftDocumentation: "What the platform asks a page's engine binding directly, answered at once.");
    public static readonly ContractRoot EnginePresentation = new(typeof(EnginePresentation), travelsToCore: false, isEngine: true,
        reachesCore: false, platformSends: false,
        swiftDocumentation: "What an engine binding tells the platform directly about one of its pages.");
    public static readonly ContractRoot EngineQuestion = new(typeof(EngineQuestion<>), travelsToCore: true, isEngine: true,
        swiftDocumentation: "What an engine binding asks the core about one of its pages while the engine waits, answered at once.");

    /// Every root, in the order the canonical description lists them.
    public static IReadOnlyList<ContractRoot> All { get; } =
        [Intent, Change, Rejection, Query, EngineCommand, EngineEvent, PageRequest, EnginePresentation, EngineQuestion];

    /// The root's C# base type; a query's is the open `Query<>`.
    public Type Type { get; }

    /// The base type's name without its generic arity: `Query` for `Query<>`.
    public string Name { get; }

    /// The core reads messages of this root, each on its own.
    public bool TravelsToCore { get; }

    /// The core reads or writes messages of this root. The platform's direct
    /// path to an engine binding never reaches it.
    public bool ReachesCore { get; }

    /// The platform encodes messages of this root and sends them, to the core
    /// or to an engine binding; it decodes the others.
    public bool PlatformSends { get; }

    /// Part of the engine contract rather than the application API.
    public bool IsEngine { get; }

    /// Each message is a question with a typed answer.
    public bool HasAnswer => Type.IsGenericTypeDefinition;

    /// The Swift declaration's documentation: the protocol a message that
    /// travels to the core conforms to, or the enum of the ones it writes.
    public string SwiftDocumentation { get; }

    /// What the Swift enum of a root the core writes conforms to.
    public string SwiftConformances { get; }

    #endregion

    #region Constructors

    private ContractRoot(Type type, bool travelsToCore, string swiftDocumentation, bool isEngine = false,
        bool reachesCore = true, bool? platformSends = null, string swiftConformances = "Sendable") {
        Type = type;
        Name = type.IsGenericTypeDefinition ? type.Name[..type.Name.IndexOf('`', StringComparison.Ordinal)] : type.Name;
        TravelsToCore = travelsToCore;
        ReachesCore = reachesCore;
        PlatformSends = platformSends ?? travelsToCore;
        IsEngine = isEngine;
        SwiftDocumentation = swiftDocumentation;
        SwiftConformances = swiftConformances;
    }

    #endregion

    #region Actions - Membership

    /// Whether `type` is one of this root's concrete messages.
    public bool Contains(Type type) => HasAnswer ? AnswerOf(type) is not null : Type.IsAssignableFrom(type);

    /// The type a question of this root answers with, or null for a type that
    /// asks nothing.
    public Type? AnswerOf(Type type) {
        for (var current = type.BaseType; current is not null; current = current.BaseType)
            if (current.IsGenericType && current.GetGenericTypeDefinition() == Type) return current.GetGenericArguments()[0];
        return null;
    }

    public override string ToString() => Name;

    #endregion
}

internal enum Primitive { Bool, Int, Long, Double, String, Guid, Date, Duration, Bytes, ULong }

/// The wire shape of one constructor parameter.
internal abstract record FieldType;

internal sealed record PrimitiveField(Primitive Kind) : FieldType;

internal sealed record EnumField(Type Type) : FieldType;

internal sealed record RecordField(Type Type) : FieldType;

/// A union: any member of `Root`, or with `Base` only the members that derive
/// from that abstract record. Either travels as the root's tag followed by the
/// member's fields.
internal sealed record RootField(ContractRoot Root, Type? Base = null) : FieldType;

internal sealed record ListField(FieldType Element) : FieldType;

internal sealed record OptionalField(FieldType Value) : FieldType;

internal sealed record SetField(Type Type) : FieldType;

/// A fixed set's user-facing English text, which Swift receives as a
/// `LocalizedStringResource`. It never crosses the wire.
internal sealed record LocalizedField : FieldType;

/// A fixed set's nested `Kinds` enum, for the one switch a platform cannot
/// avoid. Swift receives it nested in the set's struct. It never crosses the wire.
internal sealed record KindsField(Type Type) : FieldType;

internal sealed record ContractField(string Name, FieldType Type);

/// A record's user-facing English text: a `[Localized]` computed property
/// whose value is the same for every instance, the note for translators, and
/// the int field whose value it carries where it spells `%lld`. It never
/// crosses the wire; Swift receives it as a `LocalizedStringResource`.
internal sealed record RecordText(string Name, string Text, string? Comment, string? Argument);

/// A sealed positional record. Its primary-constructor parameters cross the
/// wire, followed, from the core, by the values it resolves from them: its
/// `[Resolved]` computed properties, which the core writes and never reads
/// back, so a platform sends the fields alone, as the record's seed. Its
/// `[Localized]` texts never cross it, and neither do its `Statics`: its public
/// constants and static values, which Swift receives as static literals.
internal sealed record ContractRecord(Type Type, IReadOnlyList<ContractField> Fields, IReadOnlyList<ContractField> Resolved,
    IReadOnlyList<RecordText> Texts, IReadOnlyList<ContractConstant> Statics) {
    /// The field that names a record, which an observed model keeps as its identity.
    public const string IdentityField = "Id";

    public string Name => Type.Name;

    /// What crosses the wire from the core, in order: the fields, then the
    /// resolved values. A platform sends the fields alone.
    public IReadOnlyList<ContractField> Wire => [.. Fields, .. Resolved];

    /// The Apple read model keeps it as an object observed field by field.
    public bool IsObserved => Type.IsDefined(typeof(ObservedAttribute), inherit: false);

    /// Its constructor normalizes its fields, so the platform makes it through
    /// an initializer of its own and the wire through a labeled one.
    public bool IsNormalizedOnConstruction => Type.IsDefined(typeof(NormalizedOnConstructionAttribute), inherit: false);

    /// The record has an identity of its own.
    public bool IsIdentified => Fields.Any(candidate => candidate.Name == IdentityField);

    /// The record holds a password or a file of them.
    public bool HoldsSecrets => Type.IsDefined(typeof(HoldsSecretsAttribute), inherit: false);
}

/// One concrete type of a root, with its tag, for a query its answer, and for
/// an intent or a query the most bytes one encoded message may take.
internal sealed record ContractMember(ContractRecord Record, int Tag, FieldType? Answer, int? MaximumBytes) {
    public string Name => Record.Name;
}

internal sealed record ContractEnum(Type Type, bool IsFlags, IReadOnlyList<KeyValuePair<string, int>> Members) {
    public string Name => Type.Name;
}

/// A self-describing fixed set: a sealed class whose `public static readonly`
/// instances are its members. A member's wire tag is its index in the set's
/// `All`, so `All` is append-only. Each member carries the values of the set's
/// data properties into Swift; delegate members are the core's behavior and
/// stay there. An open set also has members made at runtime, so it has no wire
/// tags and never crosses the wire. A set's public constants reach Swift as
/// static values, so a rule both languages follow is written once.
internal sealed record ContractSet(Type Type, IReadOnlyList<ContractField> Properties, IReadOnlyList<ContractSetMember> Members,
    IReadOnlyList<string> CoreOnly, bool IsOpen, IReadOnlyList<ContractConstant> Constants) {
    public string Name => Type.Name;
}

/// A fixed set's public constant, or a record's public constant or static
/// value: its name, its type and its value, spelled as set data is.
internal sealed record ContractConstant(string Name, FieldType Type, object Value);

/// One member of a fixed set: the name of its static field, its wire tag, and
/// its value for each of the set's properties, in property order. A value is a
/// primitive, a `TimeSpan`, an enum value, a `SetMemberReference`, a
/// `RecordValue`, a list of values or null.
internal sealed record ContractSetMember(string Name, int Tag, IReadOnlyList<object?> Values);

/// A data value that is a member of another fixed set.
internal sealed record SetMemberReference(Type Set, string Member);

/// A data value that is a contract record: its value for each field, in field order.
internal sealed record RecordValue(ContractRecord Record, IReadOnlyList<object?> Values);

/// A localized data value: its English text, the note for translators and the
/// value the text carries where it spells `%lld`.
internal sealed record LocalizedText(string Text, string? Comment, int? Argument);

/// A contract type the generator cannot describe.
internal sealed class ContractSchemaException(string message) : Exception(message);

/// Every contract type reachable from the roots, and the fingerprint of their
/// canonical description.
///
/// The roots are every concrete member of a `ContractRoot`, and every fixed
/// set, so a set reaches Swift before any record names it. Configurations
/// cross once, at creation or registration, so they join the closure without a
/// tag. The closure adds the records, enums and fixed sets their constructor
/// parameters and set data use. The engine contract is described a second
/// time on its own, for its own fingerprint.
internal sealed class ContractSchema {
    #region Variables

    public const int WireVersion = 1;

    /// The first word of each canonical description, naming its contract.
    private const string ApplicationContract = "crest-contracts";
    private const string EngineContract = "crest-engine";

    /// The members a fixed set declares, and the one the generator adds.
    private const string SetAll = "All";
    private const string SetName = "Name";
    private const string SetTag = "Tag";
    private const string SetKinds = "Kinds";
    private const string CommentSuffix = "Comment";
    private const string ArgumentFormat = "%lld";

    /// The field name an observed model reserves for reading its record back.
    private const string ObservedValue = "Value";

    private readonly Dictionary<Type, ContractRecord> records = [];
    private readonly Dictionary<Type, ContractEnum> enums = [];
    private readonly Dictionary<Type, ContractSet> sets = [];
    private readonly Dictionary<ContractRoot, List<ContractMember>> roots = [];
    /// The records a platform sends through their seeds: those a message it
    /// sends holds that hold [Resolved] values, themselves or in a record a
    /// field holds.
    private readonly HashSet<Type> seeded = [];
    /// The records a platform builds field by field to send: those a message
    /// it sends holds that have no seed, are no message themselves and are not
    /// normalized on construction.
    private readonly HashSet<Type> built = [];
    /// The abstract records a field narrows a root to, with their root.
    private readonly Dictionary<Type, ContractRoot> bases = [];
    private readonly NullabilityInfoContext nullability = new();

    /// Every record, root members included, in ordinal name order.
    public IReadOnlyList<ContractRecord> Records => [.. records.Values.OrderBy(record => record.Name, StringComparer.Ordinal)];

    public IReadOnlyList<ContractEnum> Enums => [.. enums.Values.OrderBy(item => item.Name, StringComparer.Ordinal)];

    public IReadOnlyList<ContractSet> Sets => [.. sets.Values.OrderBy(set => set.Name, StringComparer.Ordinal)];

    /// Every abstract record a field narrows a root to, in ordinal name order.
    public IReadOnlyList<RootField> Bases =>
        [.. bases.OrderBy(pair => pair.Key.Name, StringComparer.Ordinal).Select(pair => new RootField(pair.Value, pair.Key))];

    /// Every abstract record that members of a root the core reads derive
    /// from, in ordinal name order, whether or not a field narrows the root to
    /// it. Swift receives each as a protocol its members conform to, so a call
    /// can take one family of messages, such as the cloud transport's intents.
    public IReadOnlyList<RootField> Families =>
        [.. roots.Where(pair => pair.Key.TravelsToCore && !pair.Key.HasAnswer)
            .SelectMany(pair => pair.Value.SelectMany(member => Ancestors(member.Record.Type, pair.Key.Type))
                .Select(ancestor => (Root: pair.Key, Base: ancestor)))
            .DistinctBy(family => family.Base)
            .OrderBy(family => family.Base.Name, StringComparer.Ordinal)
            .Select(family => new RootField(family.Root, family.Base))];

    public string Canonical { get; private set; } = "";

    public byte[] Fingerprint => SHA256.HashData(Encoding.UTF8.GetBytes(Canonical));

    /// The engine contract alone: the engine roots, the registration an
    /// engine hands the core, and what they reach. An engine binding in
    /// another language, such as Chromium's C++, is generated from it.
    public ContractSchema Engine { get; private set; } = null!;

    /// The canonical description of the engine contract alone. It describes
    /// the wire and nothing the wire does not carry, so an edit anywhere else
    /// in the contracts, or to a fixed set's data and texts, leaves it, and so
    /// an engine built against it, unchanged.
    public string EngineCanonical => Engine.Canonical;

    public byte[] EngineFingerprint => SHA256.HashData(Encoding.UTF8.GetBytes(EngineCanonical));

    /// The contract the canonical description names.
    private readonly string contract;

    /// The canonical description spells fixed sets' data and records' texts,
    /// which only the platforms that receive them read.
    private readonly bool describesData;

    #endregion

    #region Constructors

    private ContractSchema(string contract, bool describesData) {
        this.contract = contract;
        this.describesData = describesData;
    }

    #endregion

    #region Actions - Loading

    /// The schema of the contract types the core's assembly exports.
    public static ContractSchema Load(Assembly core) => Load(ContractTypes(core));

    /// The contract types the core's assembly exports. The core's domain and
    /// application share its assembly, so a type is a contract by its
    /// namespace, wherever its file sits, and nothing else crosses the wire.
    public static IReadOnlyList<Type> ContractTypes(Assembly core) {
        ArgumentNullException.ThrowIfNull(core);
        return [.. core.GetExportedTypes().Where(IsContract)];
    }

    /// Whether `type` belongs to the contracts' namespace.
    public static bool IsContract(Type type) {
        ArgumentNullException.ThrowIfNull(type);
        return type.Namespace == typeof(Intent).Namespace;
    }

    /// The schema whose roots are the given types' concrete contract types,
    /// with the engine contract's own description beside it.
    public static ContractSchema Load(IEnumerable<Type> types) {
        ArgumentNullException.ThrowIfNull(types);
        var candidates = types.Where(type => type is { IsClass: true, IsAbstract: false }).ToList();
        var schema = Describing(ApplicationContract, candidates, ContractRoot.All,
            candidates.Where(typeof(Configuration).IsAssignableFrom), candidates.Where(IsFixedSet), describesData: true);
        if (candidates.FirstOrDefault(type => type.IsDefined(typeof(ObservedAttribute), false) && !schema.records.ContainsKey(type))
            is { } unreached)
            throw new ContractSchemaException($"{unreached.Name}: an [Observed] record must be one a contract message carries.");
        schema.Engine = Describing(EngineContract, candidates, [.. ContractRoot.All.Where(root => root.IsEngine)],
            candidates.Where(type => type == typeof(EngineRegistration)), [], describesData: false);
        return schema;
    }

    /// A schema whose roots are `included`'s members among `candidates`, with
    /// `configurations` and `sets` described whether or not a record names them.
    private static ContractSchema Describing(string contract, List<Type> candidates, IReadOnlyList<ContractRoot> included,
        IEnumerable<Type> configurations, IEnumerable<Type> sets, bool describesData) {
        var schema = new ContractSchema(contract, describesData);
        foreach (var root in ContractRoot.All) schema.AddRoot(root, included.Contains(root) ? candidates.Where(root.Contains) : []);
        foreach (var type in configurations.OrderBy(type => type.Name, StringComparer.Ordinal)) schema.DescribeRecord(type);
        foreach (var set in sets.OrderBy(type => type.Name, StringComparer.Ordinal)) schema.DescribeSet(set, set.Name);
        schema.Validate();
        schema.FindSeeds();
        schema.Canonical = schema.Describe();
        return schema;
    }

    private void AddRoot(ContractRoot root, IEnumerable<Type> types) {
        var ordered = types.OrderBy(type => type.Name, StringComparer.Ordinal).ToList();
        roots[root] = [.. ordered.Select((type, tag) => {
            var answer = root.AnswerOf(type) is { } answered ? ResolveRequired(answered, null, $"{type.Name} answer") : null;
            return new ContractMember(DescribeRecord(type), tag, answer, MessageLimit(type, root));
        })];
    }

    /// The byte limit of a message the core reads: its own, or the default.
    /// Nothing the core writes is read on its own, so nothing else may name one.
    private static int? MessageLimit(Type type, ContractRoot root) {
        var limit = type.GetCustomAttribute<MessageLimitAttribute>(inherit: false);
        if (!root.TravelsToCore)
            return limit is null ? null : throw new ContractSchemaException($"{type.Name}: only a message the core reads has a message limit.");
        if (limit is { Bytes: <= 0 })
            throw new ContractSchemaException($"{type.Name}: a message limit must be a positive number of bytes.");
        return limit?.Bytes ?? MessageLimitAttribute.DefaultBytes;
    }

    #endregion

    #region Actions - Records

    private ContractRecord DescribeRecord(Type type) {
        if (records.TryGetValue(type, out var known)) return known;
        if (!type.IsClass || !type.IsSealed || type.IsGenericType || !type.IsPublic)
            throw new ContractSchemaException($"{type.Name}: contract types must be public, sealed, non-generic records.");
        if (type.GetProperty("EqualityContract", BindingFlags.NonPublic | BindingFlags.Instance) is null)
            throw new ContractSchemaException($"{type.Name}: contract types must be records, or fixed sets that declare a static All.");
        var constructors = type.GetConstructors(BindingFlags.Public | BindingFlags.Instance);
        if (constructors.Length != 1)
            throw new ContractSchemaException($"{type.Name}: a contract record needs exactly one public (primary) constructor.");
        // Register before resolving fields so a record may refer to itself through a list or an optional.
        var fields = new List<ContractField>();
        var resolved = new List<ContractField>();
        var texts = new List<RecordText>();
        var statics = new List<ContractConstant>();
        var record = new ContractRecord(type, fields, resolved, texts, statics);
        records[type] = record;
        foreach (var parameter in constructors[0].GetParameters()) {
            string where = $"{type.Name}.{parameter.Name}";
            var property = type.GetProperty(parameter.Name!, BindingFlags.Public | BindingFlags.Instance);
            if (property is null || property.PropertyType != parameter.ParameterType)
                throw new ContractSchemaException($"{where}: every constructor parameter must be a positional property.");
            fields.Add(new ContractField(parameter.Name!, Resolve(parameter.ParameterType, nullability.Create(parameter), where)));
        }
        foreach (var property in type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(property => property.IsDefined(typeof(ResolvedAttribute), false)).OrderBy(property => property.MetadataToken)) {
            string where = $"{type.Name}.{property.Name}";
            if (fields.Any(field => field.Name == property.Name) || property.SetMethod is not null
                || property.GetIndexParameters().Length > 0)
                throw new ContractSchemaException($"{where}: a [Resolved] value is a get-only computed property, not a field.");
            resolved.Add(new ContractField(property.Name, Resolve(property.PropertyType, nullability.Create(property), where)));
        }
        texts.AddRange(RecordTexts(type, fields));
        statics.AddRange(RecordStatics(type));
        return record;
    }

    /// A record's public constants, then its public static values, each in the
    /// order it declares them. Swift spells each as a literal, a record through
    /// the initializer generated code makes it with, its resolved values read
    /// from the core's own instance, so a value the core names is written once.
    /// A static Swift cannot spell stops the generator; keep it non-public.
    private IEnumerable<ContractConstant> RecordStatics(Type type) {
        const BindingFlags declared = BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly;
        var fields = type.GetFields(declared).OrderBy(field => field.MetadataToken)
            .Select(field => (field.Name, Type: field.FieldType, Info: nullability.Create(field),
                Value: field.IsLiteral ? field.GetRawConstantValue() : field.GetValue(null), Writable: !field.IsLiteral && !field.IsInitOnly));
        var properties = type.GetProperties(declared).Where(property => property.GetIndexParameters().Length == 0)
            .OrderBy(property => property.MetadataToken)
            .Select(property => (property.Name, Type: property.PropertyType, Info: nullability.Create(property), Value: property.GetValue(null),
                Writable: property.SetMethod is { IsPublic: true }));
        foreach (var member in fields.Concat(properties)) {
            string at = $"{type.Name}.{member.Name}";
            if (member.Writable)
                throw new ContractSchemaException($"{at}: a record's public static value reaches Swift as a literal, so it cannot change.");
            FieldType resolved;
            try {
                resolved = ResolveSetData(member.Type, member.Info, at, type, allowsResolved: true);
            } catch (ContractSchemaException error) {
                throw new ContractSchemaException($"{at}: a record's public static value reaches Swift as a literal, and Swift cannot "
                    + $"spell this one ({error.Message}). Make it non-public.");
            }
            yield return new ContractConstant(member.Name, resolved, SetData(resolved, member.Value, at)
                ?? throw new ContractSchemaException($"{at}: a record's public static value holds null."));
        }
    }

    /// A record's `[Localized]` computed properties. Each is the same English
    /// for every instance, read from one made without its constructor, and
    /// spells `%lld` exactly once when it names the int field it carries.
    private static IEnumerable<RecordText> RecordTexts(Type type, IReadOnlyList<ContractField> fields) {
        var accessors = type.GetProperties(BindingFlags.Public | BindingFlags.Instance).OrderBy(property => property.MetadataToken).ToList();
        if (!accessors.Any(IsLocalized)) yield break;
        var comments = TranslatorComments(accessors, type.Name);
        var instance = System.Runtime.CompilerServices.RuntimeHelpers.GetUninitializedObject(type);
        foreach (var property in accessors.Where(IsLocalized)) {
            string at = $"{type.Name}.{property.Name}";
            if (fields.Any(field => field.Name == property.Name) || property.PropertyType != typeof(string) || property.SetMethod is not null)
                throw new ContractSchemaException($"{at}: a record's [Localized] text is a get-only string property outside its constructor.");
            string? argument = property.GetCustomAttribute<LocalizedAttribute>()!.Argument;
            if (argument is not null && fields.FirstOrDefault(field => field.Name == argument)?.Type is not PrimitiveField { Kind: Primitive.Int })
                throw new ContractSchemaException($"{at}: its argument {argument} must be an int field of the record.");
            if (property.GetValue(instance) is not string text || text.Split(ArgumentFormat).Length - 1 != (argument is null ? 0 : 1))
                throw new ContractSchemaException($"{at}: a record's text is constant English that spells {ArgumentFormat} exactly once "
                    + "when it names an argument, and never otherwise.");
            yield return new RecordText(property.Name, text,
                comments.TryGetValue(property, out var comment) ? (string?)comment.GetValue(instance) : null, argument);
        }
    }

    private FieldType Resolve(Type type, NullabilityInfo? info, string where) {
        if (Nullable.GetUnderlyingType(type) is { } underlying) return new OptionalField(ResolveRequired(underlying, null, where));
        if (!type.IsValueType && info?.ReadState == NullabilityState.Nullable) return new OptionalField(ResolveRequired(type, info, where));
        return ResolveRequired(type, info, where);
    }

    private FieldType ResolveRequired(Type type, NullabilityInfo? info, string where) {
        if (type == typeof(bool)) return new PrimitiveField(Primitive.Bool);
        if (type == typeof(int)) return new PrimitiveField(Primitive.Int);
        if (type == typeof(long)) return new PrimitiveField(Primitive.Long);
        if (type == typeof(ulong)) return new PrimitiveField(Primitive.ULong);
        if (type == typeof(double)) return new PrimitiveField(Primitive.Double);
        if (type == typeof(string)) return new PrimitiveField(Primitive.String);
        if (type == typeof(Guid)) return new PrimitiveField(Primitive.Guid);
        if (type == typeof(DateTimeOffset)) return new PrimitiveField(Primitive.Date);
        if (type == typeof(TimeSpan)) return new PrimitiveField(Primitive.Duration);
        if (type == typeof(byte[])) return new PrimitiveField(Primitive.Bytes);
        if (ContractRoot.All.FirstOrDefault(root => root.Type == type) is { } union) return new RootField(union);
        if (NarrowedUnion(type, where) is { } narrowed) return narrowed;
        if (type.IsEnum) return DescribeEnum(type, where);
        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(IReadOnlyList<>))
            return new ListField(Resolve(type.GetGenericArguments()[0], info?.GenericTypeArguments.FirstOrDefault(), $"{where}[]"));
        if (IsFixedSet(type)) {
            var set = DescribeSet(type, where);
            return sets[type].IsOpen
                ? throw new ContractSchemaException($"{where}: open set {type.Name} has members made at runtime, which no wire tag names.")
                : set;
        }
        if (type.IsClass && !type.IsAbstract && IsContract(type)) {
            DescribeRecord(type);
            return new RecordField(type);
        }
        throw new ContractSchemaException($"{where}: unsupported type {Display(type)}.");
    }

    /// A field typed as an abstract contract record that members of a root
    /// derive from, such as the imports among the intents, holds one of those
    /// members. Only a root the core reads narrows this way, so the core is
    /// the one reader that refuses any other member.
    private RootField? NarrowedUnion(Type type, string where) {
        if (type is not { IsClass: true, IsAbstract: true }
            || ContractRoot.All.FirstOrDefault(root => !root.HasAnswer && root.Type != type && root.Type.IsAssignableFrom(type))
                is not { } root)
            return null;
        if (!type.IsPublic || type.IsGenericType)
            throw new ContractSchemaException($"{where}: union base {type.Name} must be public and non-generic.");
        if (!root.TravelsToCore)
            throw new ContractSchemaException($"{where}: {type.Name} narrows {root.Name}, which the core writes; only a root the "
                + "core reads narrows to a base.");
        bases[type] = root;
        return new RootField(root, type);
    }

    private EnumField DescribeEnum(Type type, string where) {
        if (enums.ContainsKey(type)) return new EnumField(type);
        if (Enum.GetUnderlyingType(type) != typeof(int) || !type.IsPublic)
            throw new ContractSchemaException($"{where}: enum {type.Name} must be public and int-backed.");
        bool isFlags = type.IsDefined(typeof(FlagsAttribute), false);
        var members = Enum.GetNames(type).Select(name => new KeyValuePair<string, int>(name, (int)Enum.Parse(type, name)))
            .OrderBy(member => member.Value).ToList();
        bool valid = isFlags
            ? members.All(member => member.Value >= 0)
            : members.Select((member, index) => member.Value == index).All(matches => matches);
        if (!valid)
            throw new ContractSchemaException(isFlags
                ? $"{where}: flags enum {type.Name} must not have negative members."
                : $"{where}: enum {type.Name} must be contiguous from 0.");
        enums[type] = new ContractEnum(type, isFlags, members);
        return new EnumField(type);
    }

    private static string Display(Type type) => type.IsGenericType
        ? $"{type.Name[..type.Name.IndexOf('`', StringComparison.Ordinal)]}<{string.Join(", ", type.GetGenericArguments().Select(Display))}>"
        : type.Name;

    #endregion

    #region Actions - Fixed sets

    /// A sealed class that is not a record and declares a static `All`. The
    /// rest of the shape is checked when the set is described, so a class that
    /// nearly has it fails with the rule it broke.
    private static bool IsFixedSet(Type type) =>
        type is { IsClass: true, IsSealed: true, IsAbstract: false }
        && type.GetProperty("EqualityContract", BindingFlags.NonPublic | BindingFlags.Instance) is null
        && type.GetMember(SetAll, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static).Length > 0;

    private SetField DescribeSet(Type type, string where) {
        if (sets.ContainsKey(type)) return new SetField(type);
        string name = type.Name;
        if (!type.IsPublic || type.IsGenericType)
            throw new ContractSchemaException($"{where}: fixed set {name} must be public and non-generic.");
        if (type.GetConstructors(BindingFlags.Public | BindingFlags.Instance).Length > 0)
            throw new ContractSchemaException($"{name}: a fixed set's constructors must be private, so its static instances are its only members.");
        var instances = SetInstances(type);
        var properties = new List<ContractField>();
        var members = new List<ContractSetMember>();
        var coreOnly = new List<string>();
        var constants = new List<ContractConstant>();
        // Register before resolving properties so a data member may name this set or one that names it.
        sets[type] = new ContractSet(type, properties, members, coreOnly, type.IsDefined(typeof(OpenSetAttribute), false), constants);
        if (!describesData) {
            // Only a member's tag crosses the wire, so a contract that leaves out set data also leaves out
            // the enums and sets that data names: an engine outlives any edit to them.
            members.AddRange(instances.Select((instance, tag) => new ContractSetMember(MemberName(type, instance, $"{name}.{SetAll}[{tag}]"),
                tag, [])));
            return new SetField(type);
        }
        foreach (var constant in type.GetFields(BindingFlags.Public | BindingFlags.Static).Where(field => field.IsLiteral)) {
            string at = $"{name}.{constant.Name}";
            if (ResolveSetData(constant.FieldType, null, at, type) is not PrimitiveField primitive)
                throw new ContractSchemaException($"{at}: a fixed set's constants are bool, int, long, double or string.");
            constants.Add(new ContractConstant(constant.Name, primitive, constant.GetRawConstantValue()!));
        }
        if (type.GetFields(BindingFlags.Public | BindingFlags.Instance).FirstOrDefault() is { } exposed)
            throw new ContractSchemaException($"{name}.{exposed.Name}: a fixed set exposes its data as get-only properties, not fields.");
        coreOnly.AddRange(type.GetFields(BindingFlags.NonPublic | BindingFlags.Instance)
            .Where(field => typeof(Delegate).IsAssignableFrom(field.FieldType)).Select(field => DeclaredName(field.Name)));
        var accessors = type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(property => !typeof(Delegate).IsAssignableFrom(property.PropertyType)).OrderBy(property => property.MetadataToken).ToList();
        var comments = TranslatorComments(accessors, name);
        accessors.RemoveAll(comments.ContainsValue);
        var arguments = LocalizedArguments(accessors, name);
        foreach (var property in accessors) {
            string at = $"{name}.{property.Name}";
            if (property.Name == SetTag)
                throw new ContractSchemaException($"{at}: {SetTag} is the generated wire tag; give the property another name.");
            if (property.GetIndexParameters().Length > 0 || property.SetMethod is { IsPublic: true })
                throw new ContractSchemaException($"{at}: a fixed set's data members must be get-only properties.");
            var info = nullability.Create(property);
            properties.Add(new ContractField(property.Name, IsLocalized(property)
                ? ResolveLocalized(property.PropertyType, info, at)
                : ResolveSetData(property.PropertyType, info, at, type)));
        }
        int nameIndex = properties.FindIndex(property => property is { Name: SetName, Type: PrimitiveField { Kind: Primitive.String } });
        if (nameIndex < 0)
            throw new ContractSchemaException($"{name}: a fixed set needs a string {SetName}, which Swift's named(_:) looks up.");
        foreach (var (instance, tag) in instances.Select((instance, tag) => (instance, tag))) {
            string member = MemberName(type, instance, $"{name}.{SetAll}[{tag}]");
            members.Add(new ContractSetMember(member, tag, [.. accessors.Select((property, index) =>
                SetData(properties[index].Type, DataValue(property, instance, comments, arguments), $"{name}.{member}.{property.Name}"))]));
        }
        if (members.GroupBy(member => member.Values[nameIndex]).FirstOrDefault(group => group.Count() > 1) is { } shared)
            throw new ContractSchemaException($"{name}: {string.Join(" and ", shared.Select(member => member.Name))} share the {SetName} \"{shared.Key}\".");
        return new SetField(type);
    }

    /// The members of `All` in order, each one of the set's public static
    /// readonly instances, and every such instance listed exactly once.
    private static List<object> SetInstances(Type type) {
        string name = type.Name;
        var all = type.GetProperty(SetAll, BindingFlags.Public | BindingFlags.Static);
        if (all is null || all.PropertyType != typeof(IReadOnlyList<>).MakeGenericType(type) || all.SetMethod is { IsPublic: true }
            || all.GetValue(null) is not System.Collections.IEnumerable listed)
            throw new ContractSchemaException($"{name}.{SetAll}: a fixed set lists its members in a public static get-only IReadOnlyList<{name}>.");
        var fields = type.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static).Where(field => field.FieldType == type).ToList();
        if (fields.FirstOrDefault(field => !field.IsPublic || !field.IsInitOnly || field.GetValue(null) is null) is { } hidden)
            throw new ContractSchemaException($"{name}.{hidden.Name}: a fixed set's instances must be public static readonly fields with a value.");
        var instances = listed.Cast<object?>().ToList();
        if (instances.Count == 0)
            throw new ContractSchemaException($"{name}.{SetAll}: a fixed set needs at least one member.");
        var seen = new HashSet<object>(ReferenceEqualityComparer.Instance);
        for (int tag = 0; tag < instances.Count; tag++) {
            if (instances[tag] is not { } instance || fields.Count(field => ReferenceEquals(field.GetValue(null), instance)) != 1)
                throw new ContractSchemaException($"{name}.{SetAll}[{tag}]: every member of {SetAll} must be exactly one of the set's static readonly fields.");
            if (!seen.Add(instance))
                throw new ContractSchemaException($"{name}.{SetAll}[{tag}]: {MemberName(type, instance, name)} appears in {SetAll} more than once.");
        }
        if (fields.FirstOrDefault(field => !seen.Contains(field.GetValue(null)!)) is { } missing)
            throw new ContractSchemaException($"{name}.{missing.Name}: every instance must appear in {SetAll}, because its wire tag is its index there.");
        return [.. instances.OfType<object>()];
    }

    /// A data member Swift can spell as a literal: a primitive, a duration, an
    /// enum, another fixed set, the set's own `Kinds`, a contract record whose
    /// fields are all spellable, or a list of any of them, each optional.
    private FieldType ResolveSetData(Type type, NullabilityInfo? info, string where, Type set, bool allowsResolved = false) {
        if (Nullable.GetUnderlyingType(type) is { } underlying)
            return new OptionalField(ResolveSetData(underlying, null, where, set, allowsResolved));
        if (!type.IsValueType && info?.ReadState == NullabilityState.Nullable)
            return new OptionalField(ResolveSetData(type, null, where, set, allowsResolved));
        if (type == typeof(bool)) return new PrimitiveField(Primitive.Bool);
        if (type == typeof(int)) return new PrimitiveField(Primitive.Int);
        if (type == typeof(long)) return new PrimitiveField(Primitive.Long);
        if (type == typeof(ulong)) return new PrimitiveField(Primitive.ULong);
        if (type == typeof(double)) return new PrimitiveField(Primitive.Double);
        if (type == typeof(string)) return new PrimitiveField(Primitive.String);
        if (type == typeof(TimeSpan)) return new PrimitiveField(Primitive.Duration);
        if (type.IsEnum && type.DeclaringType == set && type.Name == SetKinds) return new KindsField(type);
        if (type.IsEnum) return DescribeEnum(type, where);
        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(IReadOnlyList<>))
            return new ListField(ResolveSetData(type.GetGenericArguments()[0], info?.GenericTypeArguments.FirstOrDefault(), $"{where}[]", set,
                allowsResolved));
        if (IsFixedSet(type)) return DescribeSet(type, where);
        if (IsRecordOf(type, set)) {
            DescribeRecord(type);
            var record = new RecordField(type);
            EnsureSpellable(record, where, [], allowsResolved);
            return record;
        }
        throw new ContractSchemaException($"{where}: a fixed set's data members are bool, int, long, double, string, TimeSpan, an enum, "
            + $"another fixed set, the set's own nested {SetKinds}, a record declared beside the set or a list of them, optionally "
            + $"nullable, and {Display(type)} is none of them. Keep other state private, or pass behavior as a delegate.");
    }

    /// A record declared beside the set that holds it: in its assembly and namespace.
    private static bool IsRecordOf(Type type, Type set) =>
        type is { IsClass: true, IsAbstract: false } && type.Assembly == set.Assembly && type.Namespace == set.Namespace
        && type.GetProperty("EqualityContract", BindingFlags.NonPublic | BindingFlags.Instance) is not null;

    /// A record held as set data is spelled with its initializer,
    /// so each of its fields must itself be a value Swift can spell. Set data
    /// cannot hold [Resolved] values, which only the core computes; a record's
    /// static value can, since the generator reads them from the core's instance.
    private void EnsureSpellable(FieldType type, string where, HashSet<Type> visiting, bool allowsResolved) {
        switch (type) {
            case PrimitiveField { Kind: Primitive.Guid or Primitive.Date }:
                throw new ContractSchemaException($"{where}: a record held as set data cannot hold a {Describe(type)}, which Swift "
                    + "cannot spell as a literal.");
            case RootField:
                throw new ContractSchemaException($"{where}: a record held as set data cannot hold a union.");
            case RecordField record:
                if (!visiting.Add(record.Type))
                    throw new ContractSchemaException($"{where}: a record held as set data cannot contain itself.");
                if (!allowsResolved && records[record.Type].Resolved.Count > 0)
                    throw new ContractSchemaException($"{where}: a record held as set data cannot have [Resolved] values, which "
                        + "only the core computes.");
                foreach (var field in records[record.Type].Wire)
                    EnsureSpellable(field.Type, $"{record.Type.Name}.{field.Name}", visiting, allowsResolved);
                visiting.Remove(record.Type);
                break;
            case ListField list:
                EnsureSpellable(list.Element, where, visiting, allowsResolved);
                break;
            case OptionalField optional:
                EnsureSpellable(optional.Value, where, visiting, allowsResolved);
                break;
        }
    }

    private static bool IsLocalized(PropertyInfo property) => property.IsDefined(typeof(LocalizedAttribute), false);

    private static FieldType ResolveLocalized(Type type, NullabilityInfo info, string where) => type == typeof(string)
        ? info.ReadState == NullabilityState.Nullable ? new OptionalField(new LocalizedField()) : new LocalizedField()
        : throw new ContractSchemaException($"{where}: only a string member can be [Localized].");

    /// Each localized member's `<Member>Comment` sibling, which reaches Swift
    /// only inside the localized value.
    private static Dictionary<PropertyInfo, PropertyInfo> TranslatorComments(IReadOnlyList<PropertyInfo> accessors, string set) {
        var comments = new Dictionary<PropertyInfo, PropertyInfo>();
        foreach (var localized in accessors.Where(IsLocalized)) {
            if (accessors.FirstOrDefault(property => property.Name == $"{localized.Name}{CommentSuffix}") is not { } comment) continue;
            if (comment.PropertyType != typeof(string) || IsLocalized(comment))
                throw new ContractSchemaException($"{set}.{comment.Name}: a translator comment is a string that is not itself [Localized].");
            comments[localized] = comment;
        }
        return comments;
    }

    /// Each localized member's argument: the int member its
    /// `[Localized(Argument = ...)]` names.
    private static Dictionary<PropertyInfo, PropertyInfo> LocalizedArguments(IReadOnlyList<PropertyInfo> accessors, string set) {
        var arguments = new Dictionary<PropertyInfo, PropertyInfo>();
        foreach (var localized in accessors.Where(IsLocalized)) {
            if (localized.GetCustomAttribute<LocalizedAttribute>()!.Argument is not { } name) continue;
            if (accessors.FirstOrDefault(property => property.Name == name) is not { } argument
                || (argument.PropertyType != typeof(int) && argument.PropertyType != typeof(int?)))
                throw new ContractSchemaException($"{set}.{localized.Name}: its argument {name} must be an int member of the set.");
            arguments[localized] = argument;
        }
        return arguments;
    }

    private static object? DataValue(PropertyInfo property, object instance, Dictionary<PropertyInfo, PropertyInfo> comments,
        Dictionary<PropertyInfo, PropertyInfo> arguments) {
        object? value = property.GetValue(instance);
        if (!IsLocalized(property) || value is not string text) return value;
        int? argument = arguments.TryGetValue(property, out var source) ? (int?)source.GetValue(instance) : null;
        bool isFormat = property.GetCustomAttribute<LocalizedAttribute>()!.IsFormat;
        if (isFormat && arguments.ContainsKey(property))
            throw new ContractSchemaException($"{instance.GetType().Name}.{property.Name}: a format takes its number from the core, "
                + "not from an argument member.");
        if (text.Split(ArgumentFormat).Length - 1 != (argument is null && !isFormat ? 0 : 1))
            throw new ContractSchemaException($"{instance.GetType().Name}.{property.Name}: \"{text}\" must spell {ArgumentFormat} exactly "
                + "once when it is a format or its argument has a value, and never otherwise.");
        return new LocalizedText(text, comments.TryGetValue(property, out var comment) ? (string?)comment.GetValue(instance) : null,
            argument);
    }

    private object? SetData(FieldType type, object? value, string where) => (type, value) switch {
        (OptionalField, null) => null,
        (OptionalField optional, _) => SetData(optional.Value, value, where),
        (_, null) => throw new ContractSchemaException($"{where}: a data member that is not nullable holds null."),
        (SetField set, _) => new SetMemberReference(set.Type, MemberName(set.Type, value, where)),
        (ListField list, System.Collections.IEnumerable items) =>
            items.Cast<object?>().Select((item, index) => SetData(list.Element, item, $"{where}[{index}]")).ToList(),
        (RecordField record, _) => RecordData(records[record.Type], value, where),
        _ => value
    };

    private RecordValue RecordData(ContractRecord record, object value, string where) => new(record, [.. record.Wire.Select(field =>
        SetData(field.Type, record.Type.GetProperty(field.Name)!.GetValue(value), $"{where}.{field.Name}"))]);

    private static string MemberName(Type set, object instance, string where) =>
        set.GetFields(BindingFlags.Public | BindingFlags.Static)
            .FirstOrDefault(field => field.FieldType == set && ReferenceEquals(field.GetValue(null), instance))?.Name
        ?? throw new ContractSchemaException($"{where}: the value is not one of {set.Name}'s static instances.");

    /// `<Applies>k__BackingField` is the field behind the property `Applies`.
    private static string DeclaredName(string field) =>
        field.StartsWith('<') && field.IndexOf('>', StringComparison.Ordinal) is > 1 and var end ? field[1..end] : field;

    #endregion

    #region Actions - Validation

    private void Validate() {
        var duplicate = records.Keys.Select(type => type.Name).Concat(enums.Keys.Select(type => type.Name))
            .Concat(sets.Keys.Select(type => type.Name)).Concat(bases.Keys.Select(type => type.Name))
            .GroupBy(name => name, StringComparer.Ordinal).FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
            throw new ContractSchemaException($"{duplicate.Key}: contract type names must be unique, because Swift has one namespace.");
        foreach (var record in records.Values)
            foreach (var field in record.Wire) ValidateLists(field.Type, $"{record.Name}.{field.Name}");
        foreach (var record in records.Values.Where(record => record.IsObserved)) ValidateObserved(record);
        foreach (var record in records.Values.Where(record => record.IsNormalizedOnConstruction)) ValidateNormalized(record);
        foreach (var narrowed in Bases)
            if (Members(narrowed).Count == 0)
                throw new ContractSchemaException($"{narrowed.Base!.Name}: a union base needs at least one concrete member of {narrowed.Root}.");
    }

    /// Marks every record that holds [Resolved] values, itself or through its
    /// fields, then keeps those a message the platform sends holds. A message
    /// it sends carries seeds and resolves nothing of its own.
    private void FindSeeds() {
        foreach (var record in records.Values.Where(record => record.Resolved.Count > 0)) {
            if (IsSent(record))
                throw new ContractSchemaException($"{record.Name}: a message the platform sends cannot carry [Resolved] values, which only the core computes.");
            seeded.Add(record.Type);
        }
        bool changed = true;
        while (changed) {
            changed = false;
            foreach (var record in records.Values.Where(record => !seeded.Contains(record.Type) && !IsSent(record)))
                if (record.Fields.Any(field => HoldsSeed(field.Type))) changed |= seeded.Add(record.Type);
        }
        var sent = new HashSet<Type>();
        var pending = new Stack<FieldType>(records.Values.Where(IsSent).SelectMany(record => record.Fields).Select(field => field.Type));
        while (pending.TryPop(out var type))
            switch (type) {
                case RecordField record when sent.Add(record.Type):
                    foreach (var field in records[record.Type].Fields) pending.Push(field.Type);
                    break;
                case ListField list: pending.Push(list.Element); break;
                case OptionalField optional: pending.Push(optional.Value); break;
            }
        seeded.IntersectWith(sent);
        built.UnionWith(sent.Where(type => !seeded.Contains(type) && !records[type].IsNormalizedOnConstruction && !IsSent(records[type])));
    }

    /// Whether a field of this type holds a record that has a seed.
    public bool HoldsSeed(FieldType type) => type switch {
        RecordField record => seeded.Contains(record.Type),
        ListField list => HoldsSeed(list.Element),
        OptionalField optional => HoldsSeed(optional.Value),
        _ => false
    };

    /// An observed model reads its record back through `value` and is told
    /// apart from its siblings by a GUID identity.
    private static void ValidateObserved(ContractRecord record) {
        if (record.Wire.FirstOrDefault(field => field.Name == ObservedValue) is { } value)
            throw new ContractSchemaException($"{record.Name}.{value.Name}: an [Observed] record's model reads the record as `value`; "
                + "give the field another name.");
        if (record.Fields.FirstOrDefault(field => field.Name == ContractRecord.IdentityField) is { } identity
            && identity.Type is not PrimitiveField { Kind: Primitive.Guid })
            throw new ContractSchemaException($"{record.Name}.{identity.Name}: an [Observed] record's identity is a Guid.");
    }

    /// A record normalized on construction reaches Swift with a labeled wire
    /// initializer, whose label needs a field to go on, and as `Hashable` over
    /// its fields, so each of them must be a value Swift can hash.
    private void ValidateNormalized(ContractRecord record) {
        if (record.Wire.Count == 0)
            throw new ContractSchemaException($"{record.Name}: a [NormalizedOnConstruction] record needs a field to normalize.");
        if (record.Wire.FirstOrDefault(field => !IsHashable(field.Type)) is { } field)
            throw new ContractSchemaException($"{record.Name}.{field.Name}: a [NormalizedOnConstruction] record is Hashable in Swift, "
                + $"so its fields are primitives, plain enums, fixed sets, other such records or lists of them, and "
                + $"{Describe(field.Type)} is none of them.");
    }

    /// Swift hashes primitives, plain enums, fixed sets and records normalized
    /// on construction, and lists and optionals of them; an option set or a
    /// union it only compares.
    private bool IsHashable(FieldType type) => type switch {
        PrimitiveField => true,
        EnumField item => !enums[item.Type].IsFlags,
        SetField => true,
        RecordField record => records[record.Type].IsNormalizedOnConstruction,
        ListField list => IsHashable(list.Element),
        OptionalField optional => IsHashable(optional.Value),
        _ => false
    };

    /// A list's count is checked against the bytes that remain, so every
    /// element must occupy at least one byte.
    private void ValidateLists(FieldType type, string where) {
        switch (type) {
            case ListField list:
                if (MinimumSize(list.Element, []) == 0)
                    throw new ContractSchemaException($"{where}: list elements must have a nonzero wire size.");
                ValidateLists(list.Element, where);
                break;
            case OptionalField optional:
                ValidateLists(optional.Value, where);
                break;
        }
    }

    private int MinimumSize(FieldType type, HashSet<Type> visiting) => type switch {
        PrimitiveField { Kind: Primitive.Bool } => 1,
        PrimitiveField { Kind: Primitive.Int } => 4,
        PrimitiveField { Kind: Primitive.Guid } => 16,
        PrimitiveField { Kind: Primitive.String or Primitive.Bytes } => 1,
        PrimitiveField => 8,
        EnumField or SetField or RootField or ListField or OptionalField => 1,
        RecordField record => RecordMinimumSize(record.Type, visiting),
        _ => throw new ContractSchemaException($"Unknown field type {type}.")
    };

    private int RecordMinimumSize(Type type, HashSet<Type> visiting) {
        if (!visiting.Add(type))
            throw new ContractSchemaException($"{type.Name}: a record cannot contain itself except through a list or an optional.");
        int size = records[type].Wire.Sum(field => MinimumSize(field.Type, visiting));
        visiting.Remove(type);
        return size;
    }

    #endregion

    #region Mutators

    /// The root's concrete types in tag order.
    public IReadOnlyList<ContractMember> Members(ContractRoot root) => roots[root];

    /// The concrete types a union field holds, in tag order: every member of
    /// its root, or those that derive from its base.
    public IReadOnlyList<ContractMember> Members(RootField union) =>
        union.Base is { } narrowed ? [.. roots[union.Root].Where(member => narrowed.IsAssignableFrom(member.Record.Type))] : roots[union.Root];

    /// Whether the platform sends `record` as a message of one of its roots:
    /// an intent, a query or an engine event, never received.
    public bool IsSent(ContractRecord record) {
        ArgumentNullException.ThrowIfNull(record);
        return ContractRoot.All.Any(root => root.PlatformSends && roots[root].Any(member => member.Record.Type == record.Type));
    }

    /// Whether a platform builds `type` to send as its seed, which carries the
    /// fields alone: a record a message it sends holds that holds [Resolved]
    /// values, itself or in a record a field holds. The core resolves the rest
    /// when it reads it, so no platform works a resolved value out.
    public bool HasSeed(Type type) => seeded.Contains(type);

    /// Whether a platform builds `type` field by field to send, as a record a
    /// message it sends holds: one with no seed, no message itself and not
    /// normalized on construction, such as a Space's branding or the app's
    /// preferences, which a settings pane edits in place before it sends them.
    public bool IsBuilt(Type type) => built.Contains(type);

    /// The facts the families below a root the platform receives declare: a
    /// property every member of the family carries, such as the page an
    /// engine presentation is about, in family then declaration order. Swift
    /// reads each through the root's enum, which answers nil for a member
    /// outside the family.
    public IReadOnlyList<(Type Family, ContractField Field)> Facts(ContractRoot root) {
        ArgumentNullException.ThrowIfNull(root);
        if (root.PlatformSends) return [];
        var families = roots[root].SelectMany(member => Ancestors(member.Record.Type, root.Type)).Distinct()
            .OrderBy(family => family.Name, StringComparer.Ordinal);
        return [.. families.SelectMany(family => family.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
            .OrderBy(property => property.MetadataToken)
            .Select(property => (family, new ContractField(property.Name,
                Resolve(property.PropertyType, nullability.Create(property), $"{family.Name}.{property.Name}")))))];
    }

    /// The abstract records `type` derives from below `root`, nearest first.
    private static IEnumerable<Type> Ancestors(Type type, Type root) {
        for (var current = type.BaseType; current is not null && current != root; current = current.BaseType)
            if (current is { IsAbstract: true, IsPublic: true, IsGenericType: false }) yield return current;
    }

    #endregion

    #region Actions - Canonical form

    /// The text the fingerprint hashes: the wire version, every enum, every
    /// fixed set's members in `All` order with their data, every record's
    /// fields and resolved values in order, and each root's tags.
    private string Describe() {
        var text = new StringBuilder();
        text.Append(contract).Append(" wire ").Append(WireVersion).Append('\n');
        foreach (var item in Enums)
            text.Append(item.IsFlags ? "flags " : "enum ").Append(item.Name)
                .Append(string.Concat(item.Members.Select(member => $" {member.Key}={member.Value}"))).Append('\n');
        foreach (var set in Sets) {
            if (!describesData) {
                // Only a member's tag crosses the wire.
                text.Append("set ").Append(set.Name).Append(string.Concat(set.Members.Select(member => $" {member.Name}={member.Tag}")))
                    .Append('\n');
                continue;
            }
            text.Append(set.IsOpen ? "open set " : "set ").Append(set.Name).Append('(')
                .Append(string.Join(", ", set.Properties.Select(property => $"{property.Name}: {Describe(property.Type)}"))).Append(')')
                .Append(string.Concat(set.Members.Select(member =>
                    $" {member.Name}={member.Tag}({string.Join(", ", member.Values.Select(DescribeValue))})"))).Append('\n');
        }
        foreach (var record in Records)
            text.Append("record ").Append(record.Name).Append('(')
                .Append(string.Join(", ", record.Fields.Select(field => $"{field.Name}: {Describe(field.Type)}"))).Append(')')
                .Append(record.Resolved.Count == 0 ? "" : $" resolved-by-core({string.Join(", ", record.Resolved.Select(field =>
                    $"{field.Name}: {Describe(field.Type)}"))})")
                .Append(!describesData ? "" : string.Concat(record.Texts.Select(item =>
                    $" {item.Name}=localized({DescribeValue(item.Text)}, {DescribeValue(item.Comment)}, {DescribeValue(item.Argument)})")))
                .Append('\n');
        foreach (var root in ContractRoot.All)
            foreach (var member in Members(root))
                text.Append(root.Name.ToLowerInvariant()).Append(' ').Append(member.Tag).Append(' ').Append(member.Name)
                    .Append(member.Answer is { } answer ? $" -> {Describe(answer)}" : "")
                    .Append(member.MaximumBytes is { } limit ? $" limit={limit.ToString(CultureInfo.InvariantCulture)}" : "").Append('\n');
        foreach (var narrowed in Bases)
            text.Append("base ").Append(narrowed.Base!.Name).Append(" of ").Append(narrowed.Root.Name.ToLowerInvariant())
                .Append(string.Concat(Members(narrowed).Select(member => $" {member.Name}"))).Append('\n');
        return text.ToString();
    }

    public static string Describe(FieldType type) => type switch {
        PrimitiveField primitive => primitive.Kind.ToString().ToLowerInvariant(),
        EnumField item => $"enum:{item.Type.Name}",
        SetField set => $"set:{set.Type.Name}",
        LocalizedField => "localized",
        KindsField kinds => $"kinds<{string.Join(", ", Enum.GetNames(kinds.Type))}>",
        RecordField record => $"record:{record.Type.Name}",
        RootField { Base: { } narrowed } root => $"union:{root.Root}/{narrowed.Name}",
        RootField root => $"union:{root.Root}",
        ListField list => $"list<{Describe(list.Element)}>",
        OptionalField optional => $"optional<{Describe(optional.Value)}>",
        _ => throw new ContractSchemaException($"Unknown field type {type}.")
    };

    private static string DescribeValue(object? value) => value switch {
        null => "null",
        bool flag => flag ? "true" : "false",
        string text => $"\"{JsonEncodedText.Encode(text)}\"",
        double number => number.ToString("R", CultureInfo.InvariantCulture),
        TimeSpan duration => $"{duration.Ticks.ToString(CultureInfo.InvariantCulture)}ticks",
        Enum flags when flags.GetType().IsDefined(typeof(FlagsAttribute), false) =>
            $"{flags.GetType().Name}({Convert.ToInt64(flags, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture)})",
        Enum kind => kind.ToString(),
        int or long or ulong => Convert.ToString(value, CultureInfo.InvariantCulture)!,
        SetMemberReference reference => $"{reference.Set.Name}.{reference.Member}",
        RecordValue record => $"{record.Record.Name}({string.Join(", ", record.Values.Select(DescribeValue))})",
        IReadOnlyList<object?> items => $"[{string.Join(", ", items.Select(DescribeValue))}]",
        LocalizedText { Argument: { } argument } text =>
            $"localized({DescribeValue(text.Text)}, {DescribeValue(text.Comment)}, {DescribeValue(argument)})",
        LocalizedText text => $"localized({DescribeValue(text.Text)}, {DescribeValue(text.Comment)})",
        _ => throw new ContractSchemaException($"Unknown set value {value}.")
    };

    #endregion
}
