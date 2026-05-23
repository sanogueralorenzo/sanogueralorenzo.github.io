# Intent Workstreams

The Intent design is split into focused workstreams so each part can evolve independently while still feeding the same language contract.

## Workstream Outputs

- [Language Design](language-design.md): canonical syntax direction, type system, goal structure, effect typing, modules, packages, and static checks.
- [Tools And Effects](tools-and-effects.md): capability declarations, typed effect signatures, adapters, denials, approvals, and rollback contracts.
- [Trust And Security](trust-security.md): trust zones, principals, capability scopes, secrets, human approval, audit events, and policy failure modes.
- [Memory And Provenance](memory-provenance.md): scoped memory, retention, erasure, summaries, evidence, citations, checkpointing, and provenance graphs.
- [Verification And Runtime](verification-runtime.md): execution graph, step lifecycle, checks, invariants, retries, cancellation, checkpoints, completion criteria, and runtime API.

## Integration Rule

`../SPEC.md` is the integrating contract. Workstream documents may explore details more deeply, but examples and future implementation work should converge on the `goal`-centered source shape in the spec.

When a workstream introduces a new language construct, it should answer:

- What static check proves the construct is valid?
- What runtime state or effect does it create?
- How does it interact with trust policy?
- How is memory scoped and retained?
- What verification gate proves the construct did its job?
- What provenance is recorded?

