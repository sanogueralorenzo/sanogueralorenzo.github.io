# State-core contract

`include/crest_core.h` and `include/crest_app.h` define
the C ABI between the Swift application and the current C# state core.
Session/application intents, queries and changes use generated binary codecs
with a shared schema fingerprint. Page lifecycle, WebKit commands and callbacks
are native and never cross this ABI.

After changing a core contract, run from the project root:

```sh
Scripts/control-plane/generate-contracts.sh
```

Add `--check` to verify generated sources without writing them. Swift releases
core-allocated responses with `crest_buffer_free`.

Page lifecycle and history are owned by Swift under
`CrestShared/Application/Pages`; local view operations remain under
`CrestShared/Infrastructure/WebKit/PageOperations`. See [the core boundary](../Documentation/Architecture/ControlPlane.md).
