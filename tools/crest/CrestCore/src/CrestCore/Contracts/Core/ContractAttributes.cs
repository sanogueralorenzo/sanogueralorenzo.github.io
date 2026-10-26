namespace CrestCore.Contracts;

/// Marks a record that holds a password or a file of them. The core keeps no
/// such record: none is reachable from a change, the session it stores or the
/// sync journal, and its text form names no secret. A containment test
/// checks both.
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class HoldsSecretsAttribute : Attribute;

/// Marks a fixed set's string member as user-facing English text. The
/// generator gives Swift a `LocalizedStringResource` built from the literal, so
/// Xcode extracts it into the string catalog. A string member named after it
/// with `Comment` appended, such as `TitleComment` for `Title`, is the note for
/// translators and reaches Swift only as the resource's comment.
[AttributeUsage(AttributeTargets.Property)]
public sealed class LocalizedAttribute : Attribute {
    #region Variables

    /// An int member of the same set whose value the text carries. Where the
    /// member has a value, the text spells it `%lld` exactly once, and Swift
    /// interpolates the value there, so every member shares the one catalog
    /// key: `Select Tab %lld` reaches Swift as "Select Tab \(3)".
    public string? Argument { get; set; }

    /// The text is a format that spells `%lld` exactly once for a number the
    /// core supplies when it writes the text into data, such as a Space's
    /// ordinal. Swift receives the format whole, localizes it and hands it back
    /// to the core, so the catalog key keeps its `%lld`.
    public bool IsFormat { get; set; }

    #endregion
}

/// Marks a record whose constructor normalizes its fields, so two spellings of
/// one value are equal: `SiteOrigin` lowercases its scheme and host and fills a
/// web scheme's default port. Every stored value is already normalized, so
/// equality and hashing over the fields are correct, and Swift receives the
/// struct as `Hashable`.
///
/// Swift's struct has no memberwise initializer. The codec makes it through a
/// labeled wire initializer, `init(normalized …)`, from values the core wrote
/// after normalizing them, and nothing else may call it; the generator refuses
/// a Swift source that does. The platform writes the initializer with the
/// natural labels, which normalizes the same way the constructor does.
///
/// It changes nothing on the wire: the schema fingerprint does not name it.
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class NormalizedOnConstructionAttribute : Attribute;

/// Marks a record the Apple read model keeps as an object views observe field
/// by field. Swift receives `<Record>Model`, a main-actor observable class with
/// one property per field, built from a value and updated from the next one by
/// assigning only the fields that differ, so a tab's new title notifies the
/// readers of that title and no one else. A record with an `Id` keeps it as the
/// model's fixed identity.
///
/// It changes nothing on the wire: the schema fingerprint does not name it.
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class ObservedAttribute : Attribute;

/// Marks a fixed set that also has members made at runtime, such as a
/// Space's custom search engines beside the built-in ones. Its static
/// instances are still the members `All` lists and `Named` finds; a runtime
/// member is made by the set's own factory and is told apart by its `Name`.
///
/// A runtime member has no index in `All`, so an open set never crosses the
/// wire. Swift receives a struct with a memberwise initializer, so a platform
/// can describe a runtime member it keeps, and two values are equal when their
/// names are.
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class OpenSetAttribute : Attribute;

/// Marks a record's computed property as a value the core resolves from the
/// record's fields and publishes with it, so no platform works out the rule
/// again: a tab arrives with its icon mode already decided.
///
/// It crosses the wire from the core after the record's fields, and Swift
/// receives it as a field of its own. It never travels to the core: where a
/// message a platform sends holds the record, the platform builds the
/// record's generated seed, its fields alone, and the core resolves the rest
/// when it reads it. No stored or synced format holds it, since the
/// hand-written codecs write only the fields.
[AttributeUsage(AttributeTargets.Property, Inherited = false)]
public sealed class ResolvedAttribute : Attribute;
