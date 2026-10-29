# State ownership

The C# `CrestCore` currently owns browser session state and the rules that edit
it: Spaces, tabs, folders, splits, window selection, page lifecycle,
remembered permission records, import readers and atomic session imports, address resolution,
persistence and sync records. `CoreState`
is the observable Swift read model. Views do not independently persist or
mutate copies of the session.

Native WebKit objects own renderer state and platform services. Local page
operations run directly in Swift. Navigation events report resulting changes
to the state core. Media-session metadata, sequencing, dismissal and Now Playing
selection belong to `BrowserMediaSessionStore`. Download records, risk and
progress rules, transfer routing and download prompts belong to
`BrowserNativeDownloads`; the closing core receives only its derived live count.
The command palette ranks immutable native snapshots of these read models;
its text matching, scopes, completion, calculation and suggestions are Swift.

The platform supplies CloudKit transport, Keychain, OS permission prompts,
notifications, file dialogs and software-update presentation. The existing
Crest features use those services through their native implementations.

The fixed command catalog, capability filtering, window availability and
numbered sidebar/Space shortcuts are native. Window records hold presentation
state; command availability is derived from the existing observed models.

The import queue, review choices, duplicate/overflow analysis and extension
selection belong to `NativeBrowserImport`. Preview and commit carry the same
explicit choices to the session’s atomic import; the core retains no UI review.

Pending page prompts are native and process-local. `NativeBrowserPrompts`
settles questions once, retires questions when pages close, and sends answers
directly to WebKit. Credentials have no core contract or persistence path.
The permission ledger remains in the core until its storage owner moves.
