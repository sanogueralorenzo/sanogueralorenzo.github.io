# Codex Everywhere Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `codex/` contain a working all-platform Flutter app plus a Raspberry Pi-hosted backend that lets laptops and phones start, resume, and stream Codex CLI conversations.

**Architecture:** Keep Codex execution on the Raspberry Pi and expose a small authenticated local API to clients. The backend wraps `codex-core noninteractive run/resume --raw-jsonl`, stores session metadata, serializes one active turn per thread, and streams turn events to clients with Server-Sent Events. The Flutter app stays a thin client: route list, thread list, chat screen, prompt composer, event stream rendering, and connection settings.

**Tech Stack:** Flutter, Mavericks, go_router, get_it/injectable, Dio/Retrofit, Freezed, TypeScript Node backend, `codex-core`, `codex exec --json`, SSE, systemd, Tailscale or LAN-only token auth.

---

## File Structure

- `codex/app`: existing all-platform Flutter client.
- `codex/app/lib/src/features/connection`: backend URL/token setup and health check.
- `codex/app/lib/src/features/sessions`: session/thread list, create, resume, archive/delete.
- `codex/app/lib/src/features/chat`: prompt composer, message/event timeline, active turn state.
- `codex/app/lib/src/network`: Dio client plus SSE client adapter.
- `codex/gateway`: new TypeScript backend for HTTP/SSE access to Codex CLI.
- `codex/gateway/src/codex`: process runner for `codex-core noninteractive`.
- `codex/gateway/src/sessions`: thread/session store and one-turn-per-thread locks.
- `codex/gateway/src/http`: REST and SSE routes.
- `codex/gateway/systemd`: Raspberry Pi service files.
- `codex/README.md`: install, run, and deployment instructions.

## Phase 1: Define The Backend Contract

- [ ] Create `codex/gateway/docs/api.md` with the exact client contract:
  - `GET /health` returns `{ "ok": true, "codexCore": "available" }`.
  - `GET /sessions` returns saved sessions ordered by `updatedAt`.
  - `POST /sessions` creates a new session with `{ "cwd": "...", "prompt": "..." }`.
  - `POST /sessions/:id/turns` appends a prompt to an existing session.
  - `GET /sessions/:id/events` streams SSE events for active and recent turns.
  - `POST /sessions/:id/cancel` cancels an active turn.
- [ ] Add example JSON payloads and SSE event names: `turn_started`, `codex_event`, `assistant_delta`, `turn_finished`, `turn_failed`.
- [ ] Verify by reviewing the document against `codex-core/README.md` and confirming the contract maps to `noninteractive run/resume`.
- [ ] Commit: `docs: define codex gateway api`.

## Phase 2: Scaffold The Gateway

- [ ] Create `codex/gateway/package.json`, `tsconfig.json`, `vitest.config.ts`, and `src/index.ts`.
- [ ] Use built-in Node HTTP plus small focused modules unless a dependency is clearly needed.
- [ ] Add scripts: `dev`, `build`, `start`, `typecheck`, `test`.
- [ ] Add a `GET /health` route that checks the configured `CODEX_CORE_BIN` is executable.
- [ ] Write `codex/gateway/src/http/health.test.ts` before implementation.
- [ ] Run: `npm install`, `npm run typecheck`, `npm run test`.
- [ ] Commit: `feat: scaffold codex gateway`.

## Phase 3: Wrap Codex CLI Execution

- [ ] Create `codex/gateway/src/codex/codex-runner.ts`.
- [ ] Implement `runNewTurn({ cwd, prompt })` using `codex-core noninteractive run --prompt-stdin --raw-jsonl`.
- [ ] Implement `resumeTurn({ threadId, cwd, prompt })` using `codex-core noninteractive resume --prompt-stdin --raw-jsonl`.
- [ ] Parse JSONL defensively: preserve raw events, derive final assistant text when present, and surface stderr on failure.
- [ ] Add tests with a fake executable script that emits JSONL and exits with both success and failure.
- [ ] Run: `npm run typecheck && npm run test`.
- [ ] Commit: `feat: wrap codex cli execution`.

## Phase 4: Add Session Store And Turn Locking

- [ ] Create `codex/gateway/src/sessions/session-store.ts`.
- [ ] Store data under `~/.codex/everywhere/sessions.json` by default, override with `CODEX_EVERYWHERE_HOME`.
- [ ] Track `id`, `threadId`, `cwd`, `title`, `updatedAt`, `activeTurnId`, and last final assistant message.
- [ ] Create `codex/gateway/src/sessions/turn-lock.ts` so a session rejects a second active prompt with HTTP 409.
- [ ] Add tests for create, update, ordering, persistence, and lock release after success/failure.
- [ ] Run: `npm run typecheck && npm run test`.
- [ ] Commit: `feat: persist codex gateway sessions`.

## Phase 5: Implement REST And SSE

- [ ] Implement `GET /sessions`, `POST /sessions`, `POST /sessions/:id/turns`, `GET /sessions/:id/events`, and `POST /sessions/:id/cancel`.
- [ ] Use SSE as the default stream because clients send prompts with HTTP POST and only need server-to-client updates during turns.
- [ ] Keep recent events in memory per session so a reconnect can replay the active turn.
- [ ] Broadcast parsed Codex JSONL events without forcing the backend to understand every possible Codex event shape.
- [ ] Add endpoint tests for success, CLI failure, concurrent prompt rejection, and SSE replay.
- [ ] Run: `npm run typecheck && npm run test`.
- [ ] Commit: `feat: stream codex turns over sse`.

## Phase 6: Add Minimal Auth And Pi Deployment

- [ ] Add `CODEX_EVERYWHERE_TOKEN`; require `Authorization: Bearer <token>` for every route except `/health`.
- [ ] Add `codex/gateway/.env.example` with `HOST`, `PORT`, `CODEX_CORE_BIN`, `CODEX_EVERYWHERE_HOME`, and `CODEX_EVERYWHERE_TOKEN`.
- [ ] Add `codex/gateway/systemd/codex-everywhere.service`.
- [ ] Document Raspberry Pi setup in `codex/README.md`: install Node, install `codex-core`, set env, enable systemd, connect through Tailscale or same LAN.
- [ ] Add auth tests for missing, invalid, and valid token.
- [ ] Run: `npm run typecheck && npm run test`.
- [ ] Commit: `feat: secure and document codex gateway`.

## Phase 7: Add Flutter Connection Feature

- [ ] Create `codex/app/lib/src/features/connection`.
- [ ] Add model `ConnectionSettings(baseUrl, token)` with secure token storage.
- [ ] Add Retrofit API for `/health`.
- [ ] Add screen to edit backend URL and token, test connection, and save settings.
- [ ] Add Mavericks ViewModel tests for loading saved settings, failed health check, and successful save.
- [ ] Wire route `/connection` in `app_router.dart`.
- [ ] Run: `flutter analyze && flutter test && flutter build web --no-pub`.
- [ ] Commit: `feat: add gateway connection settings`.

## Phase 8: Add Flutter Sessions Feature

- [ ] Create `codex/app/lib/src/features/sessions`.
- [ ] Add Retrofit models and API for `GET /sessions` and `POST /sessions`.
- [ ] Add sessions screen showing recent sessions, cwd, title, and updated time.
- [ ] Add create-session flow with cwd and first prompt.
- [ ] Add Mavericks tests for loading, empty state, create success, and create failure.
- [ ] Wire root route to sessions after connection is configured.
- [ ] Run: `flutter analyze && flutter test && flutter build web --no-pub`.
- [ ] Commit: `feat: add codex session list`.

## Phase 9: Add Flutter Chat And Streaming

- [ ] Create `codex/app/lib/src/features/chat`.
- [ ] Add an SSE client in `codex/app/lib/src/network/sse_client.dart` using `HttpClient` outside web and browser-compatible streaming on web.
- [ ] Model timeline items with Freezed: user prompt, assistant text, tool/event summary, failure.
- [ ] Add Chat ViewModel that opens `GET /sessions/:id/events`, posts prompts, appends streamed updates, and reconnects after transient disconnect.
- [ ] Add chat screen with timeline, prompt input, send, cancel, and connection status.
- [ ] Add tests using a fake SSE stream and fake session API.
- [ ] Run platform checks: `flutter analyze`, `flutter test`, `flutter build web --no-pub`, `flutter build apk --debug`, `flutter build macos --debug` on macOS.
- [ ] Commit: `feat: add streaming codex chat`.

## Phase 10: Platform Polish And Release Checks

- [ ] Confirm Flutter project supports Android, iOS, Linux, macOS, web, and Windows folders.
- [ ] Add platform permissions only where needed for network access.
- [ ] Add `codex/app/README.md` instructions for web, Android, iOS, macOS, Linux, and Windows run commands.
- [ ] Add `codex/README.md` top-level architecture diagram and quickstart.
- [ ] Run final verification:
  - `cd codex/gateway && npm run typecheck && npm run test && npm run build`
  - `cd codex/app && flutter analyze && flutter test && flutter build web --no-pub`
  - `cd codex/app && flutter build apk --debug`
  - `cd codex/app && flutter build macos --debug`
- [ ] Commit: `docs: add codex everywhere quickstart`.

## Goal Success Criteria

- [ ] Raspberry Pi runs `codex/gateway` as a service and can execute Codex through `codex-core`.
- [ ] Flutter app launches on web, Android, iOS, macOS, Linux, and Windows project targets.
- [ ] A phone or laptop can connect to the Pi, create a new Codex session, send a prompt, and receive streamed updates.
- [ ] A second device can open the same session and see the same active or completed turn.
- [ ] Backend prevents two simultaneous prompts from mutating the same session.
- [ ] Token auth is required outside health checks.
- [ ] All gateway and Flutter tests pass.

## Recommended `/goal` Prompt

Use this as the goal objective:

```text
Implement Codex Everywhere in /Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/codex: keep the existing Flutter app as the all-platform client, add a Raspberry Pi-hosted TypeScript gateway that wraps codex-core/codex CLI, expose authenticated REST plus SSE streaming for sessions and turns, wire Flutter connection/session/chat features to it, verify web/android/macos builds plus tests, and commit/push focused changes after each completed phase while leaving unrelated files untouched.
```
