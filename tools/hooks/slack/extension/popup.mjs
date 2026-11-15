const dot = document.getElementById('dot');
async function request(message) {
  const response = await chrome.runtime.sendMessage(message);
  if (!response?.ok) throw new Error(response?.error || 'Extension unavailable. Reload Browser Hooks once after updating.');
  return response.value;
}
function connection(connected, detail) {
  dot.dataset.connected = String(connected);
  dot.setAttribute('aria-label', connected ? 'Slack connected' : 'Slack disconnected');
  dot.title = detail;
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
void refresh();
const timer = setInterval(refresh, 2000);
window.addEventListener('pagehide', () => clearInterval(timer), { once: true });
