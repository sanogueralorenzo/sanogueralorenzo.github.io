const ui = Object.fromEntries(['dot', 'code', 'feedback', 'pair-form'].map(id => [id, document.getElementById(id)]));
async function request(message) {
  const response = await chrome.runtime.sendMessage(message);
  if (!response?.ok) throw new Error(response?.error || 'Extension unavailable. Reload Browser Hooks once after updating.');
  return response.value;
}
function connection(connected, detail) {
  ui.dot.dataset.connected = String(connected);
  ui.dot.setAttribute('aria-label', connected ? 'Slack connected' : 'Slack disconnected');
  ui.dot.title = detail;
}
async function refresh() {
  try {
    const config = await request({ type: 'popup.settings' });
    const tabs = await chrome.tabs.query({ url: 'https://app.slack.com/*' });
    const results = await Promise.allSettled(tabs.map(tab => chrome.tabs.sendMessage(tab.id, { type: 'slack.status' })));
    const states = results.filter(result => result.status === 'fulfilled').map(result => result.value).filter(Boolean);
    const connected = !config.error && states.some(state => state.connected);
    const error = config.error || states.find(state => state.error)?.error;
    connection(connected, error || (connected ? 'Slack connected' : tabs.length ? 'Reload your Slack tab to attach the listener.' : 'Open Slack in this browser.'));
  } catch {
    connection(false, 'Reload Browser Hooks on the Extensions page, then reload Slack.');
  }
}
ui['pair-form'].addEventListener('submit', async event => {
  event.preventDefault();
  ui.code.disabled = true;
  ui.feedback.textContent = '';
  connection(false, 'Pairing local bridge…');
  try {
    await request({ type: 'popup.pair', code: ui.code.value.trim() });
    ui.code.value = '';
    await refresh();
  } catch (error) { ui.feedback.textContent = error.message; }
  finally { ui.code.disabled = false; }
});
ui.code.addEventListener('input', () => { ui.feedback.textContent = ''; });
void refresh();
const timer = setInterval(refresh, 2000);
window.addEventListener('pagehide', () => clearInterval(timer), { once: true });
