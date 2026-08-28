export function asObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return value as Record<string, unknown>;
}

export function asArray(value: unknown): unknown[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value;
}

export function getString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

export function getNumber(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  return value;
}

export function normalizeTextToken(value: string | null): string {
  if (!value) {
    return "";
  }
  return value.toLowerCase().replace(/[^a-z0-9]/g, "");
}
