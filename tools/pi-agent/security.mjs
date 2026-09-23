const secretPatterns = [
  /\bsk-[A-Za-z0-9_-]{16,}\b/g,
  /\b\d{7,12}:[A-Za-z0-9_-]{20,}\b/g,
  /Authorization:\s*Bearer\s+[^\s]+/gi,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,
];

export function safeDisplay(value) {
  const plain = String(value)
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, "")
    .replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
  return secretPatterns.reduce((text, pattern) => text.replace(pattern, "***"), plain);
}
