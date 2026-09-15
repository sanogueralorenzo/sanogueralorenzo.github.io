import { describe, expect, it } from "vitest";
import { mapTextAction } from "./router.js";

describe("mapTextAction", () => {
  it("maps aliases to their actions", () => {
    expect(mapTextAction("new")).toBe("new");
    expect(mapTextAction("n")).toBe("new");
    expect(mapTextAction("archive topic")).toBe("archive");
    expect(mapTextAction("start")).toBe("start");
    expect(mapTextAction("h")).toBe("help");
  });

  it("returns null for unknown values", () => {
    expect(mapTextAction("unknown")).toBeNull();
  });
});
