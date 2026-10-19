import { escapeHTML } from "./view.js";

export function visibleProviders(providers, query, filter) {
  const words = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  return providers.filter(provider => {
    const matchesFilter = filter === "cloud" ? provider.cloud
      : (filter !== "api_key" || !provider.cloud) && provider.methods.some(method => method.id === filter);
    const text = `${provider.name} ${provider.id}`.toLowerCase();
    return matchesFilter && words.every(word => text.includes(word));
  });
}

export function createProviders({ state, root, api }) {
  let data;
  let open = false;
  let busy = false;
  let error = "";
  let response = "";
  let promptId;
  let query = "";
  let filter = "oauth";
  const name = id => data?.providers.find(provider => provider.id === id)?.name || "Provider";
  const safeURL = value => {
    try { const url = new URL(value); return ["https:", "http:"].includes(url.protocol) ? escapeHTML(url.href) : ""; }
    catch { return ""; }
  };
  function loginHTML() {
    const login = data?.login;
    if (!login) return "";
    if (login.status === "done" || login.status === "cancelled") return "";
    if (login.status === "failed") return `<p class="provider-error" role="alert">${escapeHTML(login.message)}</p>`;
    const prompt = login.prompt;
    const control = prompt?.type === "select"
      ? `<select id="provider-response" data-provider-response>${prompt.options.map(option => `<option value="${escapeHTML(option.id)}" ${response === option.id ? "selected" : ""}>${escapeHTML(option.label)}</option>`).join("")}</select>`
      : prompt ? `<input id="provider-response" data-provider-response type="${prompt.type === "secret" ? "password" : "text"}" value="${escapeHTML(response)}" placeholder="${escapeHTML(prompt.placeholder || "")}" autocomplete="off" autocapitalize="none" spellcheck="false" ${prompt.type === "text" ? "" : "required"} maxlength="16000">` : "";
    return `<div class="provider-login"><strong>Connect ${escapeHTML(name(login.provider))}</strong>${login.message ? `<p>${escapeHTML(login.message)}</p>` : ""}${safeURL(login.url) ? `<a class="provider-login-link" href="${safeURL(login.url)}" target="_blank" rel="noopener noreferrer">Open ${escapeHTML(name(login.provider))} sign-in ↗</a>` : ""}${login.userCode ? `<p class="provider-device-code">${escapeHTML(login.userCode)}</p>` : ""}${prompt ? `<form id="provider-login-form"><label for="provider-response">${escapeHTML(prompt.message)}</label>${control}<button class="provider-primary" type="submit" ${busy ? "disabled" : ""}>Continue</button></form>` : '<p class="provider-waiting">Waiting for connection…</p>'}<button class="provider-text-button" type="button" data-action="providers-cancel" ${busy ? "disabled" : ""}>Cancel setup</button></div>`;
  }
  function listHTML(disabled) {
    const providers = visibleProviders(data.providers, query, filter);
    const filters = [["oauth", "Sign in"], ["api_key", "API key"], ["cloud", "Cloud"]];
    return `<input type="search" class="provider-search" data-provider-search aria-label="Search providers" placeholder="Search providers…" autocomplete="off" value="${escapeHTML(query)}"><div class="provider-filters" aria-label="Authentication filters">${filters.map(([id, label]) => `<button type="button" class="provider-filter" data-action="providers-filter" data-filter="${id}" aria-pressed="${filter === id}">${label}</button>`).join("")}</div><div class="provider-list">${providers.map(provider => {
      const active = data.selected.provider === provider.id && provider.connected;
      const method = provider.methods.find(method => method.id === (filter === "cloud" ? "api_key" : filter));
      return `<div class="provider-row"><button type="button" class="provider-choice" aria-current="${active}" data-action="${provider.connected ? "providers-select" : "providers-login"}" data-provider="${escapeHTML(provider.id)}" data-method="${escapeHTML(method?.id || "")}" ${disabled || (!provider.connected && !method) ? "disabled" : ""}><span class="provider-check" aria-hidden="true">${active ? "✓" : ""}</span><span><strong>${escapeHTML(provider.name)}</strong></span></button>${provider.canLogout ? `<button type="button" class="provider-text-button" data-action="providers-logout" data-provider="${escapeHTML(provider.id)}" ${disabled ? "disabled" : ""}>Disconnect</button>` : ""}</div>`;
    }).join("") || '<p class="provider-waiting provider-empty">No matching providers</p>'}</div>`;
  }
  function html() {
    const selected = data?.providers.find(provider => provider.id === data.selected.provider);
    const model = selected?.models.find(model => model.id === data.selected.modelId);
    const ready = state.connected && selected?.connected;
    const label = ready ? `Accounts: ${selected.name} · ${model?.name || data.selected.modelId}` : "Accounts";
    const pending = data?.login?.status === "pending";
    const disabled = busy || pending || !state.connected;
    const modelPicker = selected?.connected ? `<label class="provider-model-label" for="provider-model">${escapeHTML(selected.name)} model</label><select id="provider-model" data-provider-model ${disabled ? "disabled" : ""}>${selected.models.map(model => `<option value="${escapeHTML(model.id)}" ${model.id === data.selected.modelId ? "selected" : ""}>${escapeHTML(model.name)}</option>`).join("")}</select><p class="provider-footnote">Used for new tasks. Existing conversations keep their model.</p>` : "";
    const content = !data ? '<p class="provider-waiting">Loading providers…</p>' : pending ? loginHTML() : `${listHTML(disabled)}${modelPicker}${loginHTML()}`;
    return `<div class="provider-controls"><button type="button" class="provider-trigger" data-action="providers-toggle" aria-label="${escapeHTML(label)}" aria-haspopup="dialog" aria-expanded="${open}" aria-controls="provider-menu"><span class="connection-dot ${ready ? "online" : ""}" aria-hidden="true"></span></button>${open ? `<section class="provider-menu" id="provider-menu" role="dialog" aria-label="Accounts">${content}${error ? `<p class="provider-error" role="alert">${escapeHTML(error)}</p>` : ""}</section>` : ""}</div>`;
  }
  function captureFocus() {
    const current = root.querySelector(".provider-controls");
    const focused = current?.contains(document.activeElement) ? document.activeElement : null;
    const selector = focused?.matches("[data-provider-search]") ? "[data-provider-search]"
      : focused?.matches("[data-action='providers-filter']") ? `[data-filter="${focused.dataset.filter}"]`
      : focused?.matches("[data-provider-response]") ? "[data-provider-response]"
      : focused?.matches("[data-provider-model]") ? "[data-provider-model]"
      : focused?.matches(".provider-trigger") ? ".provider-trigger" : null;
    return selector ? { selector, cursor: focused?.selectionStart } : null;
  }
  function restoreFocus(saved) {
    if (saved) {
      const target = root.querySelector(saved.selector);
      target?.focus({ preventScroll: true });
      if (typeof saved.cursor === "number" && target?.setSelectionRange) target.setSelectionRange(saved.cursor, saved.cursor);
    }
  }
  function sync() {
    const current = root.querySelector(".provider-controls");
    if (!current) return;
    const template = document.createElement("template");
    template.innerHTML = html();
    if (current.isEqualNode(template.content.firstElementChild)) return;
    const focused = captureFocus();
    const scroll = current.querySelector(".provider-list")?.scrollTop;
    current.replaceWith(template.content.firstElementChild);
    const list = root.querySelector(".provider-list");
    if (list && scroll !== undefined) list.scrollTop = scroll;
    restoreFocus(focused);
  }
  function update(next) {
    data = next;
    if (next.login?.prompt?.id !== promptId) {
      promptId = next.login?.prompt?.id;
      response = next.login?.prompt?.type === "select" ? next.login.prompt.options[0]?.id || "" : "";
    }
    sync();
  }
  async function refresh() { update(await api("/api/providers")); }
  async function run(action = async () => {}) {
    if (busy) return;
    busy = true; error = ""; sync();
    try { await action(); await refresh(); }
    catch (failure) { error = failure.message; }
    finally { busy = false; sync(); }
  }
  async function handleClick(button) {
    const action = button.dataset.action;
    if (!action?.startsWith("providers-")) return false;
    if (action === "providers-toggle") {
      open = !open; sync();
      if (open) await run();
      return true;
    }
    if (action === "providers-filter") { filter = button.dataset.filter; sync(); return true; }
    await run(async () => {
      const provider = button.dataset.provider;
      if (action === "providers-select") await api("/api/providers/select", "POST", { provider, ...(data.selected.provider === provider && { modelId: data.selected.modelId }) });
      if (action === "providers-login") await api("/api/providers/login", "POST", { provider, method: button.dataset.method });
      if (action === "providers-logout") await api("/api/providers/logout", "POST", { provider });
      if (action === "providers-cancel") await api("/api/providers/cancel", "POST", { loginId: data.login.id });
    });
    return true;
  }
  root.addEventListener("input", event => {
    if (event.target.matches("[data-provider-response]")) response = event.target.value;
    if (event.target.matches("[data-provider-search]")) { query = event.target.value; sync(); }
  });
  root.addEventListener("change", event => {
    if (event.target.matches("[data-provider-response]")) response = event.target.value;
    if (event.target.matches("[data-provider-model]")) {
      const modelId = event.target.value;
      void run(() => api("/api/providers/select", "POST", { provider: data.selected.provider, modelId }));
    }
  });
  root.addEventListener("submit", event => {
    if (event.target.id !== "provider-login-form") return;
    event.preventDefault();
    const loginId = data.login.id;
    const id = promptId;
    const value = response;
    void run(() => api("/api/providers/respond", "POST", { loginId, promptId: id, value }));
  });
  document.addEventListener("click", event => {
    if (open && !event.target.closest(".provider-controls")) { open = false; sync(); }
  });
  document.addEventListener("keydown", event => {
    if (open && event.key === "Escape") {
      event.preventDefault(); event.stopPropagation(); open = false; sync();
      root.querySelector(".provider-trigger")?.focus();
    }
  }, true);
  return { html, sync, update, handleClick, captureFocus, restoreFocus };
}
