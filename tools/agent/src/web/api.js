export async function request(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      ...(options.body && !(options.body instanceof Blob) ? { "content-type": "application/json" } : {}),
      ...options.headers,
    },
  });
  if (!response.ok) {
    let detail = `Agent returned ${response.status}.`;
    try {
      const body = await response.json();
      detail = body.error ?? detail;
    } catch {}
    throw new Error(detail);
  }
  return response.status === 204 ? null : response.json();
}

export function post(path, body) {
  return request(path, { method: "POST", body: JSON.stringify(body) });
}

export async function uploadVoice(file) {
  const response = await fetch("/v1/attachments", {
    method: "POST",
    headers: {
      "content-type": file.type || "audio/octet-stream",
      "x-agent-filename": encodeURIComponent(file.name),
    },
    body: file,
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error ?? `Agent returned ${response.status}.`);
  }
  return response.json();
}

export function watchSession(sessionId, runId, onEvent, onError) {
  const query = new URLSearchParams({ sessionId });
  if (runId) query.set("runId", runId);
  const source = new EventSource(`/v1/events?${query}`);
  source.onmessage = (message) => {
    try { onEvent(JSON.parse(message.data)); }
    catch { onError(new Error("Agent runtime sent a malformed event.")); }
  };
  source.onerror = () => onError(new Error("Reconnecting"));
  return source;
}

