const ui = Object.fromEntries(['status', 'detail', 'counts', 'dot', 'mode', 'keyword', 'code', 'feedback', 'echo-settings', 'mode-form', 'pair-form'].map(id => [id, document.getElementById(id)]));
async function request(message) {
  const response = await chrome.runtime.sendMessage(message);
  if (!response?.ok) throw new Error(response?.error || 'Extension unavailable. Reload Browser Hooks once after updating.');
  return response.value;
}
async function refresh() {
  try {
    const config = await request({ type: 'popup.settings' });
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    let state;
    if (tab?.url?.startsWith('https://app.slack.com/')) {
      try { state = await chrome.tabs.sendMessage(tab.id, { type: 'slack.status' }); } catch { /* Page needs reload after installation. */ }
    }
    ui.status.textContent = state?.error ? 'Needs attention' : state?.standby ? 'Listening in another tab' : state?.connected ? 'Listening automatically' : config.error ? 'Bridge unavailable' : 'Waiting for Slack';
    ui.dot.dataset.state = state?.connected || state?.standby ? 'connected' : state?.error ? 'error' : 'stopped';
    ui.detail.textContent = state?.error || config.error || `Keywords: ${config.keywords.join(' / ')}. Replies appear as you.`;
    ui.counts.textContent = state ? `${state.received} requests · ${state.replies} replies · ${state.pending} pending` : 'Open or reload a Slack tab to attach the listener.';
    return config;
  } catch {
    ui.status.textContent = 'Extension update needed';
    ui.detail.textContent = 'Reload Browser Hooks on the Extensions page, then reload Slack.';
  }
}
async function save(event, message) {
  event.preventDefault();
  try { await request(message); ui.feedback.textContent = 'Saved. Slack pages update automatically within five seconds.'; await refresh(); }
  catch (error) { ui.feedback.textContent = error.message; }
}
ui.mode.addEventListener('change', () => { ui['echo-settings'].hidden = ui.mode.value !== 'echo'; });
ui['mode-form'].addEventListener('submit', event => save(event, { type: 'popup.mode', mode: ui.mode.value, keyword: ui.keyword.value }));
ui['pair-form'].addEventListener('submit', async event => {
  await save(event, { type: 'popup.pair', code: ui.code.value.trim() }); ui.code.value = '';
});
const initial = await refresh();
if (initial) {
  ui.mode.value = initial.mode;
  if (initial.mode === 'echo') ui.keyword.value = initial.keywords[0];
  ui['echo-settings'].hidden = initial.mode !== 'echo';
}
const timer = setInterval(refresh, 2000);
window.addEventListener('pagehide', () => clearInterval(timer), { once: true });
