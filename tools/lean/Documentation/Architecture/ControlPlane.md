# Core boundary

`CrestCore` is the Swift connection to the C# state core. `send` dispatches a
browser intent and applies returned changes to `CoreState`; `query` reads
without changing state. Background storage and sync changes arrive through a
wake callback and are drained on the main actor.

`CrestContracts/include` defines the C ABI. The contract generator writes the
Swift records and codecs, the C# codec and the tag header. Run
`Scripts/control-plane/generate-contracts.sh` after changing a core contract.
Both sides must use the same schema fingerprint.

`Engines` registers the concrete WebKit binding and forwards core page commands
and events. Local page requests and updates are Swift types under
`Infrastructure/WebKit/PageOperations`; they have no wire codec. Media-session
ordering and lifecycle run in the native store. Launch isolation and external
web-link eligibility also run in Swift before a core is required.

Download records, progress/risk queries and WebKit download callbacks run in
Swift. `SetDownloadActivity` reports their live count to the remaining quit
preparation; the C# core holds no download records or transfer identities.

Palette matching, ranking, inline completion, scopes, calculation and suggestion
filtering run in Swift from a window snapshot. Typed address resolution still
uses the shared core navigation rule; palette rows have no wire codec.

Shortcut catalogs and bindings have no core contracts. Native menus and keys
read the same fixed catalog, and numbered selections walk the current sidebar
and available Spaces directly. Link gestures still carry native modifier bits.

The import queue and review run in Swift. `ImportReviewedSpaces` carries only
explicit source/selection/destination choices for an atomic session edit;
readers and session import validation still run in the core.

Page prompt reports, questions and answers have no wire codecs. Native WebKit
pending callbacks and `NativeBrowserPrompts` handle them directly; remembered
permission decisions use the native ledger and its SQLite table. Quit confirmation
and before-unload checking are native. `QuitBarriers` derives active Space
erasures, and `AcceptQuit` preserves the existing window restoration policy.
