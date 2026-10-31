# Agent

- This is a single-user app. For incompatible persistence changes, discard local conversation/task state instead of adding migrations or backward compatibility.
- Preserve provider credentials and preferences when resetting state.
- Use Pi's storage APIs as provided; do not modify dependency internals.
