const ui = Object.fromEntries(['status', 'detail', 'counts', 'dot', 'code', 'feedback', 'pairing', 'pair-label', 'pair-form', 'pair-button'].map(id => [id, document.getElementById(id)]));
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
    const error = config.error || state?.error;
    ui.status.textContent = config.error ? 'Bridge unavailable' : error ? 'Needs attention' : state?.standby ? 'Listening in another tab' : state?.connected ? 'Listening automatically' : 'Waiting for Slack';
    ui.dot.dataset.state = error ? 'error' : state?.connected || state?.standby ? 'connected' : 'stopped';
    ui.detail.textContent = error || `Keywords: ${config.keywords.join(' / ')}. Replies appear as you.`;
    ui.counts.textContent = state ? `${state.received} requests · ${state.replies} replies · ${state.pending} pending` : 'Open or reload a Slack tab to attach the listener.';
    ui['pair-label'].textContent = config.error ? 'Pair local bridge' : 'Repair pairing';
    return config;
  } catch {
    ui.status.textContent = 'Extension update needed';
    ui.detail.textContent = 'Reload Browser Hooks on the Extensions page, then reload Slack.';
    ui.dot.dataset.state = 'error';
  }
}
ui['pair-form'].addEventListener('submit', async event => {
  event.preventDefault();
  ui['pair-button'].disabled = true;
  ui.feedback.textContent = '';
  try {
    await request({ type: 'popup.pair', code: ui.code.value.trim() });
    ui.code.value = '';
    ui.pairing.open = false;
    ui.feedback.textContent = 'Connected. Slack listens automatically.';
    await refresh();
  } catch (error) { ui.feedback.textContent = error.message; }
  finally { ui['pair-button'].disabled = false; }
});
const initial = await refresh();
ui.pairing.open = !!initial?.error;
const timer = setInterval(refresh, 2000);
window.addEventListener('pagehide', () => clearInterval(timer), { once: true });
