
# Library style (C# and Swift)

Apply the existing repository conventions first, then these rules. Style passes must not change public namespaces, module APIs, or wire/ABI/persistence contracts solely to reorganize source. Run the repository's formatter and linter before finishing.

## Shared principles

### Section layout

Order the members of every type with a body the same way in both languages. Omit a section when it has no members; enums, bodyless records and small value types with only stored properties need no sections.

1. **Static Variables**: always at the very top of the type body, because they belong to the type rather than to any one object. This covers:
   - constants;
   - static fields and static properties;
   - a fixed set's static instances and its `All` list.

   Keep their relative order: static initializers run in textual order, so `All` stays after the instances it lists. Static *methods* are not variables; they go with the action they perform.
2. **Variables**: instance fields and **properties**, including computed and expression-bodied properties.
   - Order: data objects and collections first, then primitive state grouped by kind (or by purpose, when that makes related state easier to find).
   - A property's getter comes before its setter.
   - Preserve initializer order when changing it could affect behavior.
3. **Constructors / Initializers**: explicit constructors or `init`s, including static constructors. Static factories belong with the action they perform, unless they only forward to a constructor.
4. **Abstract Methods**: only for abstract or required members (C# abstract/interface methods; Swift overridable hooks a base class expects subclasses to supply).
5. **Actions - <purpose>**: behavior grouped under short domain names such as `Access`, `Tabs` or `Persistence`. Use as many groups as the type needs. When a purpose grows large, move it to its own partial file (C#) or extension file (Swift) named `Type.Purpose.cs` or `Type+Purpose.swift`, one purpose per file.
6. **Mutators**: explicit getter and setter methods, grouped by the state they access, getter before setter. Properties stay in Variables even with a private setter. A pure getter method may live here.

Nest sections only when a substantial type becomes easier to scan. Avoid empty or redundant labels. Keep comments with the members they explain. Reordering must not change access control, overload resolution, initialization, serialization or public behavior. Apply the layout to files you touch; do not churn untouched files unless a style pass was requested.

### Objects describe themselves

A type owns its data and every behavior that depends on that data. Do not break one concept into sibling types that act on it: a `*Codes`, `*Policy`, `*Rules`, `*Mapping`, `*Helper` or `*Utilities` class, or extension files that `switch` over its kinds. Splitting a large type by purpose into `Type.Purpose.cs` / `Type+Purpose.swift` files of the same type is fine, because it is still one type.

Prefer behavior that emerges from the data an instance is constructed with over behavior that names particular cases. A method written once over the instance's own values stays correct when a new instance is added. A method that switches over cases has to be edited every time.

### Files: behavior gets a file, plain data does not

A type with behavior is the primary type of its own file, named after it. Behavior means:
- methods, computed properties or constructor logic;
- validation;
- a fixed set's instances;
- conformances with implementations.

Large purposes split into `Type.Purpose.cs` / `Type+Purpose.swift` as above.

A type that is only data does not get a file of its own. "Only data" means its declaration holds nothing but stored data:
- a positional or bodyless record;
- a struct or class with only stored properties;
- an enum with only cases;
- a record that only extends a base to give a message its typed shape (`sealed record OpenWindow(…) : WindowIntent(…)`).

Attributes and doc comments are fine. A property that only returns a constant also counts as data, for example a rejection's `[Localized] Message => "…"`. Any other method, computed property, constructor body or static instance makes it a behavior type. Place data-only types by who uses them:

- **One owning scope.** Everything that uses the type belongs to one top-level type's scope. That scope covers the top-level type itself, types nested in it, the other types in its file, and its partial or extension files. The data type then lives in that top-level type's file, in a `Types` region at the very top of the file, above the primary type and its static variables: C# `#region Types`, Swift `// MARK: - Types`. It doesn't have to be literally one caller: several callers within that one scope still count, when the owner's file is a clean home for the type.
- **Many consumers.** The type goes into one shared file for its concept. Name the file after the concept (`Intents.cs`, `WindowIntents.cs`, `EngineEvents.cs`, `SidebarModels.swift`) and put it in that concept's folder. Group its members into regions that organize them (`#region Tabs`, `#region Windows`). Treat these like shared constants: they are types, not objects with behavior, so they do not each earn a file.

Namespaces in C# and module scope in Swift keep these names unqualified, so grouping never changes a call site. When a data type later gains behavior, move it to its own file at that point. Generated code, and any type a tool locates by file path, keep their layout.

### Self-describing fixed sets

A fixed set of kinds is one type whose static instances define its members. That covers modes, reasons, states, statuses, roles, capabilities and stored spellings. Each instance is constructed with the values that make its behavior emerge: its stored or wire spelling, labels, limits, and any rule that differs by kind, passed in as a value, closure or small strategy object. The type's methods are written once over those values and never name or switch on a particular member, so adding a kind means adding one instance and nothing else.

- **C#.** A `sealed class` with a private constructor and `public static readonly` instances, an `All` list, and lookups that search `All`:
  ```csharp
  public sealed class TabIconMode {
      public static readonly TabIconMode Automatic = new(name: "automatic", inferredFromSymbol: symbol => true);
      public static readonly TabIconMode Emoji = new(name: "emoji", inferredFromSymbol: TabIcon.IsEmoji);
      public static readonly TabIconMode Pulled = new(name: "pulled", inferredFromSymbol: _ => false);
      public static IReadOnlyList<TabIconMode> All { get; } = [Emoji, Pulled, Automatic];

      public string Name { get; }
      private readonly Func<string?, bool> inferredFromSymbol;

      public static TabIconMode? Named(string? name) => All.FirstOrDefault(mode => mode.Name == name);
      public static TabIconMode Inferred(string? symbol) => All.First(mode => mode.inferredFromSymbol(symbol));
  }
  ```
- **Swift.** The same shape as a `struct` with `static let` instances, a `static let all`, and the same lookups. It is `Hashable` and `Sendable`, and `Codable` through its spelling when it crosses a wire.
- **Nested enum.** One (`Kinds`, exposed as `Kind`) is allowed only where a switch cannot be avoided, such as a wire tag or an exhaustive mapping at a platform boundary. It is never the default way to add behavior. Do not name it `Type`: Swift reserves `.Type` for the metatype, and C# forbids a nested type and a member sharing a name.
- **Plain enums** stay only for sets whose members carry no data and no behavior.
- **Messages implement their own behavior.** A message that is one of several record types (intents, queries, events) is a union. Its cases are dispatched by polymorphism, never by a type switch, a handler interface or generated dispatch.
  - **C#.** The family's base record declares an abstract method that takes its receiver and a small context record, e.g. `internal abstract void Apply(Pages pages, PageTurn turn)`. A query family declares `TAnswer Answer(…)` instead. Each case overrides the method with its own logic, so the case's file says what it does.
  - The receiver keeps the shared state and helpers `internal`. Its whole dispatcher is `intent.Apply(this, turn)`.
  - A new case that doesn't implement the method fails to compile. There is no `default` anywhere, and no interface with a single implementer.
  - The core is one assembly (contracts, domain and application together, the same folders and namespaces), so a message can reach its receiver's internal state without making it public. The generator reads the records' data for the wire and ignores their methods.
  - **Swift.** Generated unions are enums. The behavior goes on the enum: `change.apply(to: state)`, `command.perform(on: binding)`. Each case's logic is an extension method on its payload struct, and the enum's method forwards to it with an exhaustive switch that has no `default`. A listener never picks cases with `if case` or a switch with `default: break`: the cases it acts on conform to a protocol whose method calls the listener's contract (`prompt.present(on: host)`, `change.apply(to: core, in: &batch)`). A generated union or fixed set the platform must act on takes a performer protocol with one method per member, through one hand-written forwarder with no `default` (`step.kind.take(step, on: performer)`), so a member added in the core fails to compile until every platform handles it. A Swift-owned sum type a caller would dispatch becomes a protocol with one type per case that applies itself (`event.apply(to: page)`).
  - **C++.** `std::visit` over the generated variant with one overload per case, with no `get_if` chains.
  - **Facts, not logic.** When the only difference between cases is a fact (which workspace or window a message names, whether it needs an unlocked Space, a size limit), the fact lives on the case as a base property or an attribute.
  - **Data.** Records with no behavior (changes, rejections, plain data) stay in their concept files. A message with an `Apply` or `Answer` override is a behavior type and gets its own file beside its receiver.

### Typed values, never raw codes

- **Closed semantic values** (operation names, reasons, states, statuses, kinds, roles, capability names, error codes) are self-describing fixed sets, or plain enums when they carry nothing. Decode a wire string once at the boundary, dispatch and compare on the typed value, encode it when writing. Never compare, switch on, throw, or pass raw string literals for these (`status == "supported"`, `throw Error("code")`, `error.Code == "code"`, `supports("pages")`, `execute("tab.open")`).
- Literal spellings live in exactly one place: the member instance that carries them. Raw literals are otherwise acceptable only for genuinely dynamic data, user-facing localized text, and compatibility tests that assert the external wire format.
- Preserve handling of unknown future wire values (keep routing/error behavior; do not force them through a lossy conversion). Use an open typed wrapper when the set is extensible across versions.
- **Typed models own the wire.** For any nontrivial command, response, or persisted record, create a reusable typed model that owns decoding and encoding. Decode once at the boundary, use typed properties throughout; do not scatter key lookups, parsing, or dictionary/JSON construction across action methods. Related operations may share optional fields for the same concept. Preserve unknown fields when round-tripping persisted records. Keep domain models free of transport dependencies when that boundary matters.
- Do not add a value type that only wraps one identifier (`Guid`/`UUID`) without validation or behavior; use the identifier type directly with a semantic name (`folderId`). Keep a domain type when it carries an invariant or meaningful behavior. Avoid one-letter aliases for domain objects.

### General

- Explicit, narrowest practical visibility. Immutable by default (`readonly`/`let`); constants as `const`/`static let`.
- Validate untrusted input and invariants at the owning boundary, fail early with specific errors and useful messages. Errors for exceptional cases, not routine control flow.
- Descriptive names and types. Composition, focused responsibilities, small interfaces/protocols. Expose read-only collection views when callers should not mutate.
- One primary behavior type per file named after it, with plain data grouped as described under "Files"; group files by responsibility. Imports ordered and grouped (System/Foundation first).
- Document public contracts where behavior, parameters, errors or thread-safety can't be inferred; no filler comments.
- Tests: preserve existing tests and analyzer settings; add focused arrange-act-assert coverage for changed contracts, not for section labels or source layout. Follow the repository's test-retention rules.
- Do not introduce secrets, sensitive logging, or new dependencies as part of a style pass.

## C#

- Section markers are `#region Static Variables`, `#region Variables`, `#region Constructors`, `#region Abstract Methods`, `#region Actions - <purpose>`, `#region Mutators`, applied in every type with a body including partial types and interfaces. A primary constructor stays in the declaration unless converting is safe and clarifies the class.
- In CrestCore, `.editorconfig` requires opening braces on the same line (overrides the new-line brace rule of generic C# guidance). File-scoped namespaces, four-space indentation, LF endings, one final newline.
- Nullable reference types enabled. `string.IsNullOrWhiteSpace` when whitespace is invalid; explicit `StringComparison` when comparison semantics matter.
- `var` for obvious local types; explicit parameter, return and field types.
- Fixed sets use the self-describing class shape. Never write a static `*Codes` class or extension methods over an enum to give it spellings or behavior.
- A shared named string definition is appropriate when an existing public exception or persistence contract must expose a string code; callers still use that definition. Centralize error codes in the project's code lists.
- LINQ where it helps readability; materialize deferred queries used repeatedly. Add a serialization interface only when multiple models need a real shared contract.
- Expression-bodied members for simple operations; interpolation for composed text, `StringBuilder` for repeated assembly. Dispose owned resources. `Task`/`Task<T>` with cancellation for async work, `ConfigureAwait(false)` where the caller's context is not needed, no `async void` outside event handlers.
- XML documentation on public contracts. Run the project linter (CrestCore: `Scripts/control-plane/lint-dotnet.sh`).

## Swift

- Section markers are `// MARK: - Static Variables`, `// MARK: - Variables`, `// MARK: - Initializers`, `// MARK: - Abstract Methods`, `// MARK: - Actions - <purpose>`, `// MARK: - Mutators`. `Static Variables` (including a fixed set's `static let` instances and `all`) is always at the very top. Nested types that the type's API uses follow it under `// MARK: - Types` when there are several; `CodingKeys` sits with the Codable implementation. Large purposes move to `Type+Purpose.swift` extensions (the Swift analogue of partial files); inside an extension file, one `// MARK: - Actions - <purpose>` header is enough, or none when the file name already says it.
- Protocol declarations need no sections; protocol conformances go in their own extension (`extension Type: Codable { … }`) near the end of the file or in their own file when substantial.
- **Typed codes in Swift.**
  - Fixed sets are self-describing `struct`s with `static let` instances, so their data and behavior sit on the instances. A set that must survive unknown future spellings keeps them in an instance that `named(_:)` creates, rather than failing.
  - Error codes are `enum … : Error` (or a typed code struct carried by one error type). Never match errors by string.
  - Dictionaries keyed by semantic names use the typed key (`[BrowserEngineCapability: Capability]`), not `[String: …]`.
- **Example.** Instead of `supported: ["pages", "navigation"]`, `status: "supported"` and `func supports(_ name: String)`:
  - declare `struct BrowserEngineCapability: Hashable, Sendable { static let pages = BrowserEngineCapability(name: "pages", …) … }` and a `CapabilityStatus` built the same way;
  - take `[BrowserEngineCapability]`, and expose `func supports(_ capability: BrowserEngineCapability) -> Bool`.

  The encoded JSON stays identical.
- Wire and ABI payloads are `Codable` models (encode with `JSONEncoder`, decode with `JSONDecoder`), not `[String: Any]` or `JSONSerialization` dictionaries, except when relaying a genuinely opaque payload.
- `final class` unless designed for subclassing; prefer value types. `let` over `var`. Default to `private`/`fileprivate` (the formatter's file-scoped privacy is `private`), widen only as callers need.
- No force unwraps or `try!` outside proven invariants; state the invariant with `precondition`/`preconditionFailure` and a message. `guard` for early exits.
- Concurrency: isolate UI state to `@MainActor`, make cross-actor values `Sendable`, prefer structured concurrency (`async let`, task groups) over detached tasks, and pass cancellation through long-running work.
- Keep compile-time conditions (`#if os(...)`, engine/composition flags) at composition and adapter boundaries rather than in shared logic; prefer injecting a typed capability or port.
- User-facing text uses `String(localized:)` / `LocalizedStringResource`; that is text, not a code.
- `///` documentation for non-obvious contracts.
- SwiftUI views follow the same order (stored inputs/environment/state as Variables, `init`, `body`, then subviews and helpers as Actions); defer view composition, state and performance questions to `swiftui-expert-skill` and visual design to `apple-native-swiftui-design`.
- Run the repository formatter (Crest: `.swift-format` via `Scripts/check-swift-format.sh`) and build affected targets.

## Working method

Inspect the type and its neighboring partial/extension files before moving members. Identify constructor dependencies, initialization order, and any generated or serialized shape. When replacing raw codes, confirm the encoded output is byte-for-byte unchanged (or that the change is intended and migrated). Apply the smallest semantic change needed. Run the formatter/linter and affected tests or builds, then inspect the diff for accidental behavior changes and trailing whitespace. If this is an example awaiting the user's refinement, leave it reviewable before spreading the pattern further.
