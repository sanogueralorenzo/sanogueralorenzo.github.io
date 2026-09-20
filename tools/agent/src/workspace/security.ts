const secretPatterns = [
  /\bsk-[A-Za-z0-9_-]{16,}\b/g,
  /\b\d{7,12}:[A-Za-z0-9_-]{20,}\b/g,
  /Authorization:\s*Bearer\s+[^\s]+/gi,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,
];

export function redactSecrets(value: string): string {
  return secretPatterns.reduce((text, pattern) => text.replace(pattern, "[secret redacted]"), value);
}

export function containsSecret(value: string): boolean {
  return redactSecrets(value) !== value;
}

export function isSensitivePath(path: string): boolean {
  return path.split(/[\\/]/).some((part) => /^(?:\.env(?:\..*)?|\.ssh|credentials?(?:\..*)?|secrets?(?:\..*)?|.*\.(?:pem|p12|key))$/i.test(part));
}
