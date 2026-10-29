# State ownership

The C# `CrestCore` currently owns browser session state and the rules that edit
it: Spaces, tabs, folders, splits, window selection, page lifecycle,
permissions, browser import, search, persistence and sync records. `CoreState`
is the observable Swift read model. Views do not independently persist or
mutate copies of the session.

Native WebKit objects own renderer state and platform services. Local page
operations run directly in Swift. Navigation events report resulting changes
to the state core. Media-session metadata, sequencing, dismissal and Now Playing
selection belong to `BrowserMediaSessionStore`. Download records, risk and
progress rules, transfer routing and download prompts belong to
`BrowserNativeDownloads`; the closing core receives only its derived live count.

The platform supplies CloudKit transport, Keychain, OS permission prompts,
notifications, file dialogs and software-update presentation. The existing
Crest features use those services through their native implementations.
