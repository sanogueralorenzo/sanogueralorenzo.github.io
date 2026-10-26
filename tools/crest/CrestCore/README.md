# CrestCore source layout

CrestCore is the portable browser control plane. It builds as one assembly,
`src/CrestCore`, whose folders keep the core's three concerns apart without a
project boundary between them, so a message can reach the internal state of
the area that receives it:

| Folder or project | Responsibility |
| --- | --- |
| `src/CrestCore/Contracts` | The typed contract records (intents, changes, rejections, queries, engine commands and events, and the read models they carry), plus the JSON protocol validation policy requests use. Namespace `CrestCore.Contracts`. |
| `src/CrestCore/Domain` | Tab and Space behavior, durable state, navigation, and sync policy. No JSON or native dependencies. Namespace `CrestCore.Domain`. |
| `src/CrestCore/Application` | Session commands, the session file, imports, and sync transitions. It owns the JSON-backed native and persistence formats and the SQLite file they are stored in, and calls typed domain rules. Namespace `CrestCore.Application`. |
| `src/CrestCore.Native` | C exports that adapt native callers to the application layer, and the generated wire codec. |
| `tools/CrestCore.Generator` | Generates the codec, the Swift models and the C tag header from the contract records: the types the core exports in the `CrestCore.Contracts` namespace, wherever their files sit. It reads each record's data and ignores its methods. |
| `CrestCore.Tests` | Behavioral contracts for the corresponding source areas. |

The folders keep the layering the separate projects had: domain code uses
only the contracts, and the contracts use neither the domain nor the
application. The one exception is a message that carries its own behavior,
such as a page intent: its record keeps the `CrestCore.Contracts` namespace,
has its own file beside the area that receives it (`Application/Pages/Intents`
and `Events` beside `Pages`), and overrides the method its family declares
with its own logic.

Source folders follow the browser concepts they own. In the domain, `Tabs`
contains tab state and its batch, lifecycle, and organization rules; `Spaces`
contains Space ownership and preferences; `State` contains durable snapshots;
`Sync` contains portable record policy; `Navigation` contains URL, link, and
history rules; and `Identity` contains shared time and ID sources. Domain
objects use named `Guid` properties for identities without adding one-field wrappers.
The application groups session operations, sync operations, and status
separately, and gives each other browser area it serves, such as downloads,
credentials, or portability, a folder of its own. A type with behavior has its
own file, and partial classes keep related operations together under the
owning type's name. Data-only records and enums share their concept's file,
such as `Windows/WindowMessages.cs`, or sit in a `Types` region at the top of
the one type that uses them.

Keep typed domain objects inside the control plane. Decode JSON at an input
boundary, apply browser rules through domain objects, then encode JSON at an
output boundary. The application layer retains JSON when preserving the native
session and sync formats. Preserve the existing protocol and C ABI when moving
source files. File-scoped namespaces remain stable across folders so native
callers do not need new type names.

The repository `.editorconfig` controls C# layout, including same-line opening
braces. Run `Scripts/control-plane/lint-dotnet.sh` and the .NET tests before
committing changes. App-code commits also need a patch version and a release
note entry as described in the repository instructions.
