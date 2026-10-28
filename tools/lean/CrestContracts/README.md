# State-core contract

`include/crest_core.h`, `include/crest_app.h` and `include/crest_engine.h` define
the C ABI between the Swift application and the current C# state core.
Application intents, queries, changes and WebKit page events use generated
binary codecs with a shared schema fingerprint.

After changing a core contract, run from the project root:

```sh
Scripts/control-plane/generate-contracts.sh
```

Add `--check` to verify generated sources without writing them. Swift releases
core-allocated responses with `crest_buffer_free`.

Native page operations and updates are owned by Swift under
`CrestShared/Infrastructure/WebKit/PageOperations`. They have no C++ interface
or generated wire codec. See [the core boundary](../Documentation/Architecture/ControlPlane.md).
