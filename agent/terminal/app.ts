import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { decodeKittyPrintable, isKeyRelease, matchesKey, ProcessTerminal, TuiAltScreen } from "@earendil-works/pi-tui";
import type { Data, HomeMessage, Turn } from "../src/state.ts";
import { agentClient, type Accounts, type Conversation } from "./api.ts";
import { conversationRows, dependencies, replyTarget, sessionTurns, suggestionTarget, type Feed, type Row, type Target } from "./conversation.ts";
import { savedDrafts, type Draft } from "./drafts.ts";
import { bold, clean, compact, dim, green, terminalView, yellow, type Button } from "./view.ts";

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
  const queued = new Set<string>();
  const sending = new Set<string>();
  const suggestions = new Map<string, string>();
  const dismissed = new Set<string>();
  let accounts: Accounts | undefined;
  let menu: { provider?: string; cursor: number } | undefined;
  let accountBusy = false;
  let selection: string | undefined;
  let rows: Row[] = [];
  let accountActions: Button[] = [];
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
  const { top, footer, transcript, scroll, editor, showAccounts } = terminalView(tui, focusComposer);
  const feed = (): Feed => ({ data, conversation: conversations.get(view), progress, view });
  const selected = () => rows.find(row => row.id === selection);
  const button = (label: string, run: () => void): Button => ({ label, run });
  const targetOf = ({ id, text, role, sessionId }: Target): Target => ({ id, text, role, sessionId });

  function changeDraft(draft: Draft, id = view) {
    drafts.set(id, draft);
    if (id !== view || draft.text === editor.getExpandedText()) return;
    changingEditor = true;
    editor.setText(clean(draft.text));
    changingEditor = false;
  }

  function focusComposer() {
    const row = selected();
    if (row?.replyable && row.sessionId) {
      const draft = drafts.get(view);
      changeDraft({ text: draft.text, reply: targetOf(row) });
    }
    selection = undefined;
    tui.setFocus(editor);
    draw();
  }

  function scrollTo(id?: string, offset?: number) {
    scroll.scrollToEnd();
    if (id === undefined && offset === undefined) return;
    tui.renderNow();
    const position = id === undefined ? offset : transcript.positions.get(id);
    if (position !== undefined) scroll.scrollTo(position, { disableFollow: true });
  }

  function navigate(next: string) {
    if (next === view && !menu) return;
    if (!menu) saveScroll();
    menu = undefined;
    selection = undefined;
    view = next;
    drafts.select(view);
    changeDraft(drafts.get(view));
    tui.setFocus(editor);
    tui.resetTextSelection();
    const first = next === "home" ? rowsForHome().find(row => unseen.has(row.id))?.id : undefined;
    if (next === "home") unseen.clear();
    draw();
    scrollTo(first, scrolls.get(next));
  }

  function rowsForHome() {
    return conversationRows({ data, progress, view: "home" });
  }

  function saveScroll() {
    if (scroll.isFollowingEnd) scrolls.delete(view);
    else scrolls.set(view, scroll.scrollTop);
  }

  async function action(run: () => Promise<unknown>) {
    error = "";
    try { await run(); }
    catch (failure) { if (!abort.signal.aborted) error = (failure as Error).message; }
    draw();
  }

  function post(path: string, body: object) {
    if (online) void action(() => api.request(path, body));
  }

  function edit(row: Row) {
    if (!row.editable) return;
    changeDraft({ text: row.text, edit: { target: targetOf(row), previous: drafts.get(view) } });
    selection = undefined;
    focusComposer();
  }

  function approve(row: Row) {
    if (!online || row.role !== "Agent" || !row.replyable || !row.sessionId || reacted(row.id)) return;
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

  function queueAction(turn: Turn, kind: "edit" | "delete" | "steer") {
    if (!online || queued.has(turn.id)) return;
    const origin = view;
    queued.add(turn.id);
    void action(async () => {
      try {
        const result = await api.request<{ turn: Turn; message?: HomeMessage; removedMessageId?: string }>(
          kind === "steer" ? "steer-queued" : "dequeue", { sessionId: turn.sessionId, turnId: turn.id });
        if (kind === "edit") {
          const text = result.message?.text || result.turn.text;
          changeDraft({
            text, reply: replyTarget({ ...feed(), view: turn.sessionId, conversation: conversations.get(turn.sessionId) }, turn.replyToId),
            queuedEdit: { sessionId: turn.sessionId, text, previous: drafts.get(origin) },
          }, origin);
          if (view === origin && !menu) {
            selection = undefined;
            focusComposer();
          }
        }
      } finally { queued.delete(turn.id); }
    });
  }

  async function send() {
    const origin = view;
    const draft = drafts.get(origin);
    const text = draft.text.trim();
    if (!online || !text || sending.has(origin)) return;
    const target = draft.edit?.target || draft.reply;
    if (draft.edit && !data.turns.some(turn => turn.sourceId === target?.id && turn.status === "running")) {
      error = "This turn has finished. Cancel the edit and reply with a follow-up.";
    } else if (draft.edit && text === target?.text) {
      error = "Change the message before sending a revision.";
    } else {
      const sessionId = target?.sessionId || draft.queuedEdit?.sessionId || (origin === "home" ? undefined : origin);
      const previous = draft.edit?.previous || draft.queuedEdit?.previous || { text: "" };
      const id = randomUUID();
      const suggestion = suggestionTarget(feed());
      if (suggestion) dismissed.add(suggestionKey(suggestion));
      sending.add(origin);
      changeDraft(previous);
      if (origin === "home") data.messages.push({
        id, text, createdAt: new Date().toISOString(), entryId: null,
        replyToId: draft.reply?.id, editOfId: draft.edit?.target.id, status: sessionId ? "routed" : "routing",
      });
      scroll.scrollToEnd();
      draw();
      await action(async () => {
        try {
          if (sessionId) await api.request("turns", { id, text, sessionId,
            mode: draft.edit ? "steer" : "followUp", editOfId: draft.edit?.target.id, replyToId: draft.reply?.id });
          else await api.request("home", { id, text });
        } catch (failure) {
          if (!abort.signal.aborted && drafts.get(origin).text === previous.text &&
              drafts.get(origin).reply === previous.reply && drafts.get(origin).edit === previous.edit &&
              drafts.get(origin).queuedEdit === previous.queuedEdit) changeDraft(draft, origin);
          data.messages = data.messages.filter(message => message.id !== id);
          throw failure;
        } finally { sending.delete(origin); }
      });
      return;
    }
    draw();
  }

  const suggestionKey = (value: { sessionId: string; replyId: string }) => `${value.sessionId}:${value.replyId}`;

  function suggestion(showDismissed = false) {
    const draft = drafts.get(view);
    if (!online || draft.text || draft.edit || draft.queuedEdit) return;
    const target = suggestionTarget(feed());
    if (!target || (draft.reply && draft.reply.id !== target.replyId)) return;
    const key = suggestionKey(target);
    if (!suggestions.has(key)) {
      suggestions.set(key, "");
      void api.request<{ text: string | null }>("suggestions", target).then(result => {
        suggestions.set(key, result.text || "");
        draw();
      }).catch(() => {});
    }
    const text = suggestions.get(key);
    if (text && (showDismissed || !dismissed.has(key))) return { ...target, text, key };
  }

  function acceptSuggestion() {
    const hint = suggestion(true);
    if (!hint) return false;
    const reply = replyTarget(feed(), hint.replyId);
    if (!reply) return false;
    changeDraft({ text: hint.text, reply });
    focusComposer();
    return true;
  }

  function escape() {
    if (menu) { closeAccounts(); return; }
    if (selection) { selection = undefined; focusComposer(); return; }
    const draft = drafts.get(view);
    const edit = draft.edit || draft.queuedEdit;
    if (edit) changeDraft(edit.previous);
    else if (draft.reply) {
      const hint = suggestions.get(suggestionKey({ sessionId: draft.reply.sessionId ?? view, replyId: draft.reply.id }));
      changeDraft({ text: draft.text === hint ? "" : draft.text });
    } else {
      const hint = suggestion();
      if (hint) dismissed.add(hint.key);
      else error = "";
    }
    draw();
  }

  async function updateAccounts(path = "providers", body?: object) {
    if (!online || accountBusy) return;
    accountBusy = true;
    draw();
    await action(async () => {
      try { accounts = await api.request<Accounts>(path, body); }
      finally { accountBusy = false; }
    });
  }

  function toggleAccounts() {
    if (menu) { closeAccounts(); return; }
    saveScroll();
    selection = undefined;
    menu = { cursor: 0 };
    tui.setFocus(null);
    draw();
    scrollTo(undefined, 0);
    void updateAccounts();
  }

  function closeAccounts() {
    menu = undefined;
    focusComposer();
    scrollTo(undefined, scrolls.get(view));
  }

  function accountPage(provider?: string) {
    menu = { provider, cursor: 0 };
    draw();
    scrollTo(undefined, 0);
  }

  function accountBlocks() {
    accountActions = [];
    const choice = (label: string, run: () => void) => {
      const index = accountActions.length;
      const item = button(`${menu?.cursor === index ? "› " : ""}${label}`, run);
      accountActions.push(item);
      return item;
    };
    const provider = accounts?.providers.find(item => item.id === menu?.provider && item.connected);
    if (provider && online) return [
      { buttons: [choice(`← ${provider.name}`, () => accountPage())] },
      ...provider.models.map(model => {
        const active = accounts?.selected.provider === provider.id && accounts?.selected.modelId === model.id;
        return { buttons: [choice(`${active ? "✓ " : ""}${model.name}`, () => {
          void updateAccounts("providers/select", { provider: provider.id, modelId: model.id });
        })] };
      }),
    ];
    return accounts?.providers.map(item => {
      const connected = online && item.connected;
      const status = !online ? "Status unavailable" : connected ? "Connected"
        : item.installed ? `Sign in on the host with ${item.loginCommand}` : "CLI not installed";
      const buttons = connected ? [choice(item.name, () => accountPage(item.id))] : [];
      if (connected && item.fastSupported) buttons.push(choice(`Fast mode ${item.fastEnabled ? "on" : "off"}`, () => {
        void updateAccounts("providers/fast", { provider: item.id, enabled: !item.fastEnabled });
      }));
      return { header: `${connected ? green("●") : dim("○")} ${bold(item.name)} · ${dim(status)}`, buttons };
    }) ?? [{ text: online ? "Loading accounts…" : "Status unavailable" }];
  }

  function queueButtons(turn: Turn, steer: boolean) {
    if (!online || queued.has(turn.id)) return [];
    const buttons = [button("Edit", () => queueAction(turn, "edit")), button("Delete", () => queueAction(turn, "delete"))];
    if (steer) buttons.push(button("Steer", () => queueAction(turn, "steer")));
    return buttons;
  }

  function select(row: Row) {
    selection = row.id;
    tui.setFocus(null);
    draw();
  }

  function rowBlock(row: Row) {
    const active = row.id === selection;
    const label = [row.role, row.title && compact(row.title), row.detail && compact(row.detail)].filter(Boolean).join(" · ");
    const buttons: Button[] = [];
    if (active && row.title && row.sessionId) buttons.push(button("Open · Enter", () => navigate(row.sessionId!)));
    if (row.resume && online) buttons.push(button("Continue", () => post("resume", { entryId: row.resume })));
    if (active && row.replyable) buttons.push(button("Reply · Tab", focusComposer));
    if (active && row.editable && online) buttons.push(button("Edit and steer", () => edit(row)));
    if (active && row.turn) buttons.push(...queueButtons(row.turn, false));
    if (active && row.role === "Agent" && row.replyable && online && !reacted(row.id)) {
      buttons.push(button("👍 Go ahead · y", () => approve(row)));
    }
    const quote = row.quote && dim(`│ ${row.quote.role} · ${compact(row.quote.text).slice(0, 80)}`);
    return {
      id: row.id, header: (active ? bold : dim)(`${active ? "›" : " " } ${label}${reacted(row.id) ? " 👍" : ""}`),
      quote, text: row.text, markdown: row.role === "Agent", buttons, select: () => select(row),
    };
  }

  function draw() {
    if (abort.signal.aborted) return;
    const session = data.sessions.find(item => item.id === view);
    const ready = online && accounts?.providers.some(item => item.connected);
    const provider = online && accounts?.providers.find(item => item.id === accounts?.selected.provider && item.connected);
    const model = provider && provider.models.find(item => item.id === accounts?.selected.modelId);
    const nav = [];
    if (view !== "home" && !menu) nav.push(button(unseen.size ? "← Home · new replies" : "← Home", () => navigate("home")));
    nav.push(button(menu ? "Close accounts · Esc" : "Accounts · Ctrl+P", toggleAccounts));
    top.lines = [
      ` ${bold(menu ? "Accounts" : compact(session?.title || "Agent"))}  ${ready ? green("●") : dim("○")}${model && provider ? dim(` ${provider.name} · ${model.name}`) : ""}`,
      nav,
    ];
    footer.lines = [];
    showAccounts(!!menu);
    if (menu) {
      transcript.blocks = accountBlocks();
      if (accountBusy) footer.lines.push(dim("Checking accounts…"));
    } else {
      rows = conversationRows(feed());
      if (selection && !selected()) {
        selection = undefined;
        tui.setFocus(editor);
      }
      const running = session?.status === "running";
      const queue = sessionTurns(feed()).filter(turn => turn.status === "queued");
      transcript.blocks = rows.map(rowBlock);
      if (!rows.length) transcript.blocks.push({ text: view === "home" ? "How can I help?" : "No messages yet." });
      if (queue.length) transcript.blocks.push({ header: bold("Queued follow-ups") }, ...queue.map(turn => ({
        text: data.messages.find(message => message.id === turn.sourceId)?.reaction ? "👍 Go ahead" : turn.text,
        header: dependencies(data, turn) ? dim(`Waiting for ${compact(dependencies(data, turn)!)}`) : undefined,
        buttons: queueButtons(turn, running),
      })));
      if (running) footer.lines.push(dim("Working…"));
      if (session?.status === "interrupted") footer.lines.push(dim("Stopped. Return to Home to continue."));
      const draft = drafts.get(view);
      const target = draft.edit?.target || draft.reply;
      if (target || draft.queuedEdit) {
        const label = draft.edit ? "Editing and steering" : draft.queuedEdit ? "Editing queued message" : `Reply to ${target?.role}`;
        footer.lines.push(dim(`${label} · ${compact(target?.text || draft.queuedEdit?.text || "")}`));
      }
      const hint = !selection && suggestion();
      if (hint) footer.lines.push(dim(`Tab · ${compact(hint.text)}`));
      const controls: Button[] = [];
      if (running && online) controls.push(button("Stop", () => post("stop", { sessionId: view })));
      if (draft.text.trim() && online) controls.push(button("Send", () => { void send(); }));
      if (target || draft.queuedEdit) controls.push(button("Cancel · Esc", escape));
      if (controls.length) footer.lines.push(controls);
      footer.lines.push(dim(selection
        ? "Type or press Tab to compose · Esc to clear selection"
        : `Enter to send · Shift+Enter for a new line${target || draft.queuedEdit ? " · Esc to cancel" : ""}`));
    }
    if (!online) footer.lines.unshift(yellow(`Connecting to ${url.origin}…`));
    if (error) footer.lines.unshift(yellow(compact(error)), [button("Dismiss", () => { error = ""; draw(); })]);
    tui.requestRender();
  }

  function chooseRow(offset: number) {
    if (!rows.length) return;
    const index = rows.findIndex(row => row.id === selection);
    const next = rows[Math.max(0, Math.min(rows.length - 1, index < 0 ? rows.length - 1 : index + offset))];
    selection = next.id;
    tui.setFocus(null);
    const position = transcript.positions.get(next.id);
    if (position !== undefined && (position < scroll.scrollTop || position >= scroll.scrollTop + scroll.viewportHeight)) scroll.scrollTo(position);
    draw();
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
    if (matchesKey(input, "ctrl+p")) { toggleAccounts(); return consume; }
    if (matchesKey(input, "ctrl+g")) { navigate("home"); return consume; }
    if (matchesKey(input, "escape")) { escape(); return consume; }
    if (menu) {
      if (matchesKey(input, "up") || matchesKey(input, "down") || matchesKey(input, "tab")) {
        const delta = matchesKey(input, "up") ? -1 : 1;
        menu.cursor = Math.max(0, Math.min(accountActions.length - 1, menu.cursor + delta));
        draw();
      } else if (matchesKey(input, "enter")) accountActions[menu.cursor]?.run();
      return consume;
    }
    if (matchesKey(input, "alt+up") || matchesKey(input, "alt+down")) {
      chooseRow(matchesKey(input, "alt+up") ? -1 : 1);
      return consume;
    }
    const row = selected();
    if (matchesKey(input, "tab")) {
      if (row || !acceptSuggestion()) focusComposer();
      return consume;
    }
    if (row) {
      if (matchesKey(input, "enter") && row.title && row.sessionId) { navigate(row.sessionId); return consume; }
      if (matchesKey(input, "y") && row.role === "Agent" && row.replyable) { approve(row); return consume; }
      if (decodeKittyPrintable(input) || /^[^\x00-\x1f\x7f]/.test(input) || input.startsWith("\x1b[200~")) focusComposer();
    }
    if (editor.focused && (input === "\n" || matchesKey(input, "ctrl+j") || matchesKey(input, "shift+enter"))) return;
    if (matchesKey(input, "enter") && editor.focused) { void send(); return consume; }
    if (input.startsWith("\x1b[200~") && input.endsWith("\x1b[201~")) {
      return { data: `\x1b[200~${clean(input.slice(6, -6))}\x1b[201~` };
    }
  });
  editor.onChange = () => {
    if (changingEditor) return;
    drafts.set(view, { ...drafts.get(view), text: editor.getExpandedText() });
    draw();
  };
  editor.setText(clean(drafts.get(view).text));
  tui.setFocus(editor);
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
    } else if (event.type === "providers") accounts = event.data;
    else if (event.type === "progress") progress.set(event.sourceId, event.text);
    else if (event.type === "conversation") {
      conversations.set(event.sessionId, event);
      if (event.sessionId !== view) return;
    }
    draw();
  }, connected => { online = connected; draw(); });
}
