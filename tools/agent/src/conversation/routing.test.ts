import { describe, expect, it } from "vitest";
import { maySwitchContext, requiresHandoff } from "./routing.js";

describe("context switch preflight", () => {
  it("recognizes project and conversation switches with follow-on work", () => {
    for (const text of [
      "Go to project X and fix the tests",
      "Open the repository and explain its build",
      "Checkout this project and run its tests",
      "Resume the conversation about the runtime and continue",
      "Take me back to the bot restart work",
    ]) expect(maySwitchContext(text)).toBe(true);
  });

  it("keeps ordinary work on the direct path", () => {
    for (const text of ["Fix the tests", "Summarize this", "Continue working on the code"])
      expect(maySwitchContext(text)).toBe(false);
  });

  it("does not run follow-on work in the old context when an explicit switch fails", () => {
    expect(requiresHandoff("Go to project X and fix the tests")).toBe(true);
    expect(requiresHandoff("Resume the purple otter conversation and summarize it")).toBe(true);
    expect(requiresHandoff("Open the repository and fix it")).toBe(true);
    expect(requiresHandoff("Explain how to open the project")).toBe(false);
  });
});
