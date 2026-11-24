import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { decodeKittyPrintable, isKeyRelease, isKeyRepeat, matchesKey, ProcessTerminal, TuiAltScreen } from "@earendil-works/pi-tui";
import type { Data } from "../src/state.ts";
import { agentClient, type Conversation } from "./api.ts";
import { conversationRows, queuedRows, type Row, type Target } from "./conversation.ts";
import { savedDrafts, type Draft } from "./drafts.ts";
import { bold, clean, compact, dim, terminalView, yellow, type Button } from "./view.ts";

export function runTerminal(url: URL) {
  const abort = new AbortController();
  const api = agentClient(url, abort.signal);
  const drafts = savedDrafts(url, message => {
    if (abort.signal.aborted) console.error(message);
    else { error = message; draw(); }
  });
  let view = drafts.view;
  let data: Data = { messages: [], entries: [], sessions: [], turns: [] };
  let online = false;
  let loaded = false;
  let error = "";
  const conversations = new Map<string, Conversation>();
  const progress = new Map<string, string>();
  const scrolls = new Map<string, number>();
  const unseen = new Set<string>();
  const reactions = new Set<string>();
  const sending = new Set<string>();
  const changingRun = new Set<string>();
  const buttons = new Map<string, Button>();
  let rows = new Map<string, Row>();
  let stops: string[] = [];
  let focus = "composer";
  let clickedRow = false;
  let changingEditor = false;

  const tui = new TuiAltScreen(new ProcessTerminal(), true, undefined, {
    mouse: true, wheelScrollLines: 3,
    openUrl(href) {
      const target = new URL(href, url);
      if (!["https:", "http:", "mailto:"].includes(target.protocol)) return;
      const command = process.platform === "darwin" ? "open" : "xdg-open";
      const child = spawn(command, [target.href], { stdio: "ignore" });
      child.on("error", failure => { error = failure.message; draw(); });
    },
  });
  const { top, footer, transcript, scroll, editor } = terminalView(tui, () => focusComposer(rows.get(focus)));

  function button(id: string, label: string, run: () => void) {
    const item = { id, label, run, focused: focus === id };
    buttons.set(id, item);
    return item;
  }

  function setFocus(next: string) {
    focus = next;
    clickedRow = false;
    tui.setFocus(next === "composer" ? editor : null);
  }

  function moveFocus(next: string) {
    setFocus(next);
    const position = transcript.positions.get(next);
    if (position !== undefined && (position < scroll.scrollTop || position >= scroll.scrollTop + scroll.viewportHeight)) {
      scroll.scrollTo(position);
    }
    draw();
  }

  function changeDraft(draft: Draft, id = view) {
    drafts.set(id, draft);
    if (id !== view || draft.text === editor.getExpandedText()) return;
    changingEditor = true;
    editor.setText(clean(draft.text));
    changingEditor = false;
  }

  function focusComposer(row?: Row) {
    if (row?.replyable && row.sessionId) {
      const { id, text, role, sessionId } = row;
      const reply: Target = { id, text, role, sessionId };
      changeDraft({ text: drafts.get(view).text, reply });
    }
    moveFocus("composer");
  }

  function navigate(next: string) {
    if (next === view) return;
    if (scroll.isFollowingEnd) scrolls.delete(view);
    else scrolls.set(view, scroll.scrollTop);

    view = next;
    error = "";
    drafts.select(view);
    changeDraft(drafts.get(view));
    setFocus("composer");
    tui.resetTextSelection();
    const first = next === "home" ? conversationRows({ data, progress, view }).find(row => unseen.has(row.id)) : undefined;
    if (next === "home") unseen.clear();
    scroll.scrollToEnd();
    draw();
    if (first || scrolls.has(next)) {
      tui.renderNow();
      const position = first ? transcript.positions.get(`row:${first.id}`) : scrolls.get(next);
      if (position !== undefined) scroll.scrollTo(position, { disableFollow: true });
    }
  }

  async function action(run: () => Promise<unknown>) {
    error = "";
    try { await run(); }
    catch (failure) { if (!abort.signal.aborted) error = (failure as Error).message; }
    draw();
  }

  function runControl(sessionId: string, path: "stop" | "resume", body: object) {
    if (!online || changingRun.has(sessionId)) return;
    changingRun.add(sessionId);
    void action(async () => {
      try { await api.request(path, body); }
      finally { changingRun.delete(sessionId); }
    });
  }

  function approve(row: Row) {
    if (!online || !row.sessionId || reacted(row.id)) return;
    const sessionId = row.sessionId;
    reactions.add(row.id);
    draw();
    void action(async () => {
      try {
        await api.request("turns", { id: randomUUID(), sessionId, text: "Yes, go ahead.", mode: "followUp",
          replyToId: row.id, reaction: "thumbs-up" });
      } finally { reactions.delete(row.id); }
    });
  }

  function reacted(id: string) {
    return reactions.has(id) || data.messages.some(message => message.replyToId === id && message.reaction === "thumbs-up");
  }

  function send() {
    const origin = view;
    const draft = drafts.get(origin);
    const text = draft.text.trim();
    if (!online || !text || sending.has(origin)) return;
    const sessionId = draft.reply?.sessionId || (origin === "home" ? undefined : origin);
    const id = randomUUID();
    sending.add(origin);
    changeDraft({ text: "" });
    if (origin === "home") data.messages.push({
      id, text, createdAt: new Date().toISOString(), entryId: null, replyToId: draft.reply?.id,
      status: sessionId ? "routed" : "routing",
    });
    scroll.scrollToEnd();
    draw();
    void action(async () => {
      try {
        if (sessionId) await api.request("turns", { id, text, sessionId, mode: "followUp", replyToId: draft.reply?.id });
        else await api.request("home", { id, text });
      } catch (failure) {
        const current = drafts.get(origin);
        if (!abort.signal.aborted && !current.text && !current.reply) changeDraft(draft, origin);
        data.messages = data.messages.filter(message => message.id !== id);
        throw failure;
      } finally { sending.delete(origin); }
    });
  }

  function enterRow(row: Row) {
    if (view === "home" && row.sessionId) navigate(row.sessionId);
    else if (row.replyable) focusComposer(row);
  }

  function escape() {
    const draft = drafts.get(view);
    if (rows.has(focus) || draft.reply) {
      if (draft.reply) changeDraft({ text: draft.text });
      focusComposer();
    } else if (view !== "home") {
      navigate("home");
    } else {
      error = "";
      focusComposer();
    }
  }

  function rowBlock(id: string, row: Row) {
    const focused = focus === id;
    const label = [row.role, row.title && compact(row.title), row.detail && compact(row.detail)].filter(Boolean).join(" · ");
    const quote = row.quote && dim(`│ ${row.quote.role} · ${compact(row.quote.text).slice(0, 80)}`);
    return {
      id, header: (focused ? bold : dim)(`${focused ? "›" : " "} ${label}${reacted(row.id) ? " 👍" : ""}`),
      quote, text: row.text, markdown: row.role === "Agent",
      select: rows.has(id) ? (clickCount: number) => {
        if (clickCount === 2 && view === "home" && row.sessionId) { navigate(row.sessionId); return; }
        setFocus(id);
        clickedRow = true;
        draw();
      } : undefined,
    };
  }

  function draw() {
    if (abort.signal.aborted) return;
    buttons.clear();
    const feed = { data, conversation: conversations.get(view), progress, view };
    const session = data.sessions.find(item => item.id === view);
    const messages = conversationRows(feed);
    rows = new Map(messages.filter(row => row.replyable || (view === "home" && row.sessionId)).map(row => [`row:${row.id}`, row]));

    const home = view === "home" ? [] : [button("home", unseen.size ? "← Home · new replies" : "← Home", () => navigate("home"))];
    top.lines = [` ${bold(compact(session?.title || "Agent"))}`];
    if (home.length) top.lines.push(home);

    transcript.blocks = messages.map(row => rowBlock(`row:${row.id}`, row));
    if (!messages.length) transcript.blocks.push({ text: view === "home" ? "How can I help?" : "No messages yet." });
    const queue = queuedRows(feed);
    if (queue.length) transcript.blocks.push({ header: bold("Queued follow-ups") }, ...queue.map(item => ({
      header: dim(compact(item.detail)), text: item.text,
    })));

    const running = session?.status === "running";
    const interrupted = session?.status === "interrupted";
    const runButtons: Button[] = [];
    if (online && running) {
      runButtons.push(button("stop", "Stop", () => runControl(session.id, "stop", { sessionId: session.id })));
    } else if (online && interrupted) {
      const entry = data.entries.find(item => item.sessionId === view && item.status === "interrupted");
      if (entry) runButtons.push(button("continue", "Continue", () => runControl(session.id, "resume", { entryId: entry.id })));
    }
    stops = ["composer", ...runButtons.map(item => item.id), ...home.map(item => item.id), ...[...rows.keys()].reverse()];
    if (!stops.includes(focus)) {
      setFocus("composer");
      draw();
      return;
    }

    const reply = drafts.get(view).reply;
    const row = rows.get(focus);
    footer.lines = [];
    if (!online) footer.lines.push(yellow(`Connecting to ${url.origin}…`));
    if (error) footer.lines.push(yellow(compact(error)));
    if (running) footer.lines.push(dim("Working…"));
    if (interrupted) footer.lines.push(dim("Paused"));
    if (runButtons.length) footer.lines.push(runButtons);
    if (reply) footer.lines.push(dim(`Reply to ${reply.role} · ${compact(reply.text)}`));
    if (row) footer.lines.push(dim(view === "home" ? "Enter opens · Type to reply" : "Type to reply · Esc clears selection"));
    else if (focus === "composer") {
      footer.lines.push(dim(`Enter sends · ${reply ? "Esc clears quote" : view === "home" ? "Tab moves focus" : "Esc goes Home"}`));
    }
    tui.requestRender();
  }

  function quit() {
    if (abort.signal.aborted) return;
    abort.abort();
    tui.stop();
    drafts.flush();
    process.stdout.write("", () => process.exit());
  }

  const consume = { consume: true } as const;
  tui.addInputListener(input => {
    if (isKeyRelease(input)) return;
    if (matchesKey(input, "ctrl+c")) {
      if (tui.hasActiveSelection()) void tui.copyActiveSelectionToClipboard();
      else quit();
      return consume;
    }
    if (matchesKey(input, "escape")) {
      if (!isKeyRepeat(input)) escape();
      return consume;
    }
    const row = rows.get(focus);
    const tab = matchesKey(input, "tab");
    if (tab || matchesKey(input, "shift+tab")) {
      if (tab && clickedRow && row?.replyable) focusComposer(row);
      else {
        const delta = tab ? 1 : -1;
        moveFocus(stops[(stops.indexOf(focus) + stops.length + delta) % stops.length]);
      }
      return consume;
    }
    if (matchesKey(input, "enter") && input !== "\n" && !matchesKey(input, "shift+enter") && !matchesKey(input, "ctrl+j")) {
      if (isKeyRepeat(input)) return consume;
      if (focus === "composer") send();
      else if (row) enterRow(row);
      else buttons.get(focus)?.run();
      return consume;
    }
    if (row?.role === "Agent" && row.replyable && matchesKey(input, "y")) {
      approve(row);
      return consume;
    }
    if (focus !== "composer" && (decodeKittyPrintable(input) || /^[^\x00-\x1f\x7f]/.test(input) || input.startsWith("\x1b[200~"))) {
      focusComposer(row);
    }
    if (input.startsWith("\x1b[200~") && input.endsWith("\x1b[201~")) {
      return { data: `\x1b[200~${clean(input.slice(6, -6))}\x1b[201~` };
    }
  });
  editor.onChange = () => {
    if (changingEditor) return;
    const { reply } = drafts.get(view);
    drafts.set(view, { text: editor.getExpandedText(), reply });
    draw();
  };
  editor.setText(clean(drafts.get(view).text));
  setFocus("composer");
  process.once("SIGINT", quit);
  process.once("SIGTERM", quit);
  draw();
  tui.start();

  void api.follow(event => {
    if (event.type === "snapshot") {
      const known = new Set(data.entries.flatMap(entry => entry.updates.map(update => update.id)));
      data = event.data;
      const active = new Set(data.turns.map(turn => turn.sourceId));
      for (const source of progress.keys()) if (!active.has(source)) progress.delete(source);
      if (view !== "home" && !data.sessions.some(session => session.id === view)) navigate("home");
      if (loaded && view !== "home") for (const entry of data.entries) {
        if (entry.sessionId === view) continue;
        for (const update of entry.updates) if (update.kind !== "progress" && !known.has(update.id)) unseen.add(update.id);
      }
      loaded = true;
    } else if (event.type === "progress") progress.set(event.sourceId, event.text);
    else if (event.type === "conversation") {
      conversations.set(event.sessionId, event);
      if (event.sessionId !== view) return;
    } else return;
    draw();
  }, connected => { online = connected; draw(); });
}
