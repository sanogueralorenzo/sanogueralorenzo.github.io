import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    mockReset: true,
    restoreMocks: true,
    unstubEnvs: true,
    include: ["src/**/*.test.ts"],
    testTimeout: 10_000,
  },
});
