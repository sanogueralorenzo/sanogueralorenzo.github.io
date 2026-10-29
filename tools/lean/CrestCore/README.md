# State core

This directory contains the remaining C# browser state, rules, SQLite storage
and sync records. The app registers one WebKit binding. Engine-kind mappings,
default-engine preferences and cross-engine history are absent.

- `src/CrestCore`: contracts, domain rules and application state.
- `src/CrestCore.Native`: C exports and the generated binary codec.
- `tools/CrestCore.Generator`: Swift models/codecs and C tag generation.
- `tests/CrestCore.Tests`: behavioral tests and stored-data fixtures.

Use the .NET SDK pinned in `global.json`. From this directory:

```sh
dotnet test tests/CrestCore.Tests/CrestCore.Tests.csproj
```

From the browser root, run `Scripts/control-plane/lint-dotnet.sh` for C# style
and contract checks. Native page operations, launch isolation and media sessions
are owned by Swift and do not cross this boundary.
