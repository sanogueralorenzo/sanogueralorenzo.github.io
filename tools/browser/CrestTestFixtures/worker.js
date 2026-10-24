self.onmessage = event => {
  if (event.data === 'probe') self.postMessage('worker-ready');
};
