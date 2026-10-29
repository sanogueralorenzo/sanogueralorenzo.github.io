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
