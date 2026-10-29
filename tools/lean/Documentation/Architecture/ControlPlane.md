# Core boundary

`CrestCore` is the Swift connection to the C# state core. `send` dispatches a
browser intent and applies returned changes to `CoreState`; `query` reads
without changing state. Background storage and sync changes arrive through a
wake callback and are drained on the main actor.

`CrestContracts/include` defines the C ABI. The contract generator writes the
Swift records and codecs, the C# codec and the tag header. Run
`Scripts/control-plane/generate-contracts.sh` after changing a core contract.
Both sides must use the same schema fingerprint.

`Engines` hosts the concrete WebKit binding. `NativePages` handles page lifecycle,
restoration, residency, crash recovery, popup adoption and history directly.
There is no engine ABI, engine schema, command relay or page wire codec. Local
view operations remain under `Infrastructure/WebKit/PageOperations`. Media
ordering, launch isolation and external web-link eligibility also run in Swift.

The session accepts only completed page records (navigation, title and icon),
with its existing atomic persistence rules. Copy/split edits carry the native
appearance captured for the issuing window. Native command delivery preserves
handover and teardown before UI observers; synchronous reports follow the batch
that caused them.

Page presentation, blocked-popup indications, authentication handling, scheme
routing, local-document acceptance, secure-origin checks and notification
consent are native rules. Permission types and origin normalization have no
C# contracts or wire codecs; their saved names remain unchanged.

Download records, progress/risk queries and WebKit download callbacks run in
Swift. Native quit preparation reads their live count directly; the C# core
holds no download records or transfer identities.

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
and before-unload checking are native. Website-data reads and erasures have no
wire codecs. Their native owner tracks active profile erasures for quit and
validates success before dispatching a Space-removal commit. `AcceptQuit`
preserves the existing window restoration policy.
