# State ownership

The C# `CrestCore` currently owns browser session state and the rules that edit
it: Spaces, tabs, folders, splits, window selection, page lifecycle,
import readers and atomic session imports, address resolution,
persistence and sync records. `CoreState`
is the observable Swift read model. Views do not independently persist or
mutate copies of the session.

Native WebKit objects own renderer state and platform services. Local page
operations run directly in Swift. Navigation events report resulting changes
to the state core. Media-session metadata, sequencing, dismissal and Now Playing
selection belong to `BrowserMediaSessionStore`. Download records, risk and
progress rules, transfer routing and download prompts belong to
`BrowserNativeDownloads`; native quit preparation reads its derived live count.
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
Remembered permissions, session overrides, revocation and notification
eligibility are native. The native permission store owns only its existing
SQLite table; C# device records no longer carry permission rows. Whole-file
recovery backups still include them. Seeded and private workspaces keep choices
in memory, and borrowed windows use their owner’s choices.

Close and quit preparation is native. Pages are checked in opening order,
one at a time; a new document invalidates an earlier approval. Native downloads
provide the quit prompt count. Native website-data operations call WebKit
directly, own in-flight erasures and per-run success proof, and prevent Space
removal until erasure succeeds. The session core still records accepted quits
for window restoration and commits Space removals atomically.
