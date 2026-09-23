import { describe, expect, it } from "vitest";
import { containsSecret, isSensitivePath, redactSecrets } from "./security.js";

describe("secret boundaries", () => {
  it("redacts common credentials before persistence", () => {
    const text = "Authorization: Bearer abc123 and sk-abcdefghijklmnopqrstuvwxyz";
    expect(containsSecret(text)).toBe(true);
    expect(redactSecrets(text)).not.toContain("abc123");
    expect(redactSecrets(text)).not.toContain("sk-");
    expect(redactSecrets(text)).toBe("*** and ***");
  });

  it("recognizes sensitive project paths", () => {
    expect(isSensitivePath("config/.env.production")).toBe(true);
    expect(isSensitivePath("keys/service.pem")).toBe(true);
    expect(isSensitivePath("src/config.ts")).toBe(false);
  });
});
