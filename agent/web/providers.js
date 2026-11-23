import { escapeHTML, icon } from "./view.js";

export function createProviders({ state, root, api }) {
  let data;
  let open = false;
  let busy = false;
  let error = "";
  let modelProvider;
  function listHTML(disabled) {
    return `<div class="provider-list">${data.providers.map(provider => {
      const connected = state.connected && provider.connected;
      const status = !state.connected ? "Status unavailable" : connected ? "Connected" : provider.installed
        ? `Sign in on the host with <code>${escapeHTML(provider.loginCommand)}</code>` : "CLI not installed";
      const content = `<span class="connection-dot ${connected ? "online" : ""}" aria-hidden="true"></span><span><strong>${escapeHTML(provider.name)}</strong><span class="provider-status">${status}</span></span>`;
      const choice = connected
        ? `<button type="button" class="provider-choice" aria-current="${data.selected.provider === provider.id}" data-action="providers-models" data-provider="${escapeHTML(provider.id)}" ${disabled ? "disabled" : ""}>${content}</button>`
        : `<div class="provider-choice provider-offline">${content}</div>`;
      const fast = connected && provider.fastSupported
        ? `<button type="button" class="provider-fast" data-action="providers-fast" data-provider="${escapeHTML(provider.id)}" aria-label="${escapeHTML(provider.name)} fast mode" aria-pressed="${provider.fastEnabled}" title="${provider.fastEnabled ? "Disable" : "Enable"} fast mode · Higher usage cost" ${disabled ? "disabled" : ""}>${icon("lightning", 17)}</button>` : "";
      return `<div class="provider-row">${choice}${fast}</div>`;
    }).join("")}</div>`;
  }
  function modelsHTML(provider, disabled) {
    return `<button type="button" class="provider-text-button provider-back" data-action="providers-back" aria-label="Back to providers"><span aria-hidden="true">←</span><strong>${escapeHTML(provider.name)}</strong></button><div class="provider-list" aria-label="${escapeHTML(provider.name)} models">${provider.models.map(model => {
      const active = data.selected.provider === provider.id && data.selected.modelId === model.id;
      return `<div class="provider-row"><button type="button" class="provider-choice" aria-current="${active}" data-action="providers-select" data-provider="${escapeHTML(provider.id)}" data-model="${escapeHTML(model.id)}" ${disabled ? "disabled" : ""}><span class="provider-check" aria-hidden="true">${active ? "✓" : ""}</span><span><strong>${escapeHTML(model.name)}</strong></span></button></div>`;
    }).join("")}</div>`;
  }
  function html() {
    const selected = data?.providers.find(provider => provider.id === data.selected.provider && provider.connected);
    const model = selected?.models.find(model => model.id === data.selected.modelId);
    const ready = state.connected && data?.providers.some(provider => provider.connected);
    const label = ready ? `Accounts: ${selected ? `${selected.name} · ${model?.name || data.selected.modelId}` : "Connected"}` : "Accounts";
    const disabled = busy || !state.connected;
    const browsing = data?.providers.find(provider => provider.id === modelProvider && provider.connected);
    const content = !data ? '<p class="provider-waiting">Loading providers…</p>' : browsing ? modelsHTML(browsing, disabled) : listHTML(disabled);
    return `<div class="provider-controls"><button type="button" class="provider-trigger" data-action="providers-toggle" aria-label="${escapeHTML(label)}" aria-haspopup="dialog" aria-expanded="${open}" aria-controls="provider-menu"><span class="connection-dot ${ready ? "online" : ""}" aria-hidden="true"></span></button>${open ? `<section class="provider-menu" id="provider-menu" role="dialog" aria-label="Accounts">${content}${error ? `<p class="provider-error" role="alert">${escapeHTML(error)}</p>` : ""}</section>` : ""}</div>`;
  }
  function captureFocus() {
    const current = root.querySelector(".provider-controls");
    const focused = current?.contains(document.activeElement) ? document.activeElement : null;
    if (!focused?.dataset.action) return null;
    const selector = `[data-action="${focused.dataset.action}"]`;
    if (focused.dataset.model) return `${selector}[data-model="${CSS.escape(focused.dataset.model)}"]`;
    return focused.dataset.provider ? `${selector}[data-provider="${CSS.escape(focused.dataset.provider)}"]` : selector;
  }
  function restoreFocus(selector) { if (selector) root.querySelector(selector)?.focus({ preventScroll: true }); }
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
    if (modelProvider && !next.providers.some(provider => provider.id === modelProvider && provider.connected)) modelProvider = undefined;
    sync();
  }
  async function run(action) {
    if (busy) return;
    const focused = captureFocus();
    busy = true; error = ""; sync();
    try { update(await action()); }
    catch (failure) { error = failure.message; }
    finally {
      busy = false; sync();
      if (document.activeElement === document.body) restoreFocus(focused);
    }
  }
  async function handleClick(button) {
    const { action, provider, model } = button.dataset;
    if (!action?.startsWith("providers-")) return false;
    if (action === "providers-toggle") {
      open = !open;
      if (open) modelProvider = undefined;
      sync();
      if (open) await run(() => api("/api/providers"));
    } else if (action === "providers-models" || action === "providers-back") {
      modelProvider = action === "providers-models" ? provider : undefined;
      sync(); root.querySelector(".provider-list")?.scrollTo(0, 0);
      root.querySelector(action === "providers-models" ? ".provider-back" : `[data-action="providers-models"][aria-current="true"]`)?.focus();
    } else if (action === "providers-select") {
      await run(() => api("/api/providers/select", "POST", { provider, modelId: model }));
    } else if (action === "providers-fast") {
      await run(() => api("/api/providers/fast", "POST", { provider, enabled: !data.providers.find(item => item.id === provider).fastEnabled }));
    }
    return true;
  }
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
