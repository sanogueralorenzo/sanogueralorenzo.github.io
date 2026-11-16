const dot = document.getElementById('dot');
const port = chrome.runtime.connect({ name: 'popup' });
function connection(connected, detail) {
  dot.dataset.connected = String(connected);
  dot.setAttribute('aria-label', connected ? 'Slack connected' : 'Slack disconnected');
  dot.title = detail;
}
port.onMessage.addListener(message => {
  if (message.type === 'status') connection(message.connected, message.detail);
});
port.onDisconnect.addListener(() => connection(false, 'Extension disconnected. Reopen this popup.'));
window.addEventListener('pagehide', () => port.disconnect(), { once: true });
