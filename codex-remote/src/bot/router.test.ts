import { describe, expect, it } from "vitest";
import { mapTextAction } from "./router.js";

describe("mapTextAction", () => {
  it("maps aliases to their actions", () => {
    expect(mapTextAction("new")).toBe("new");
    expect(mapTextAction("n")).toBe("new");
    expect(mapTextAction("resume chat")).toBe("resume");
    expect(mapTextAction("delete")).toBe("delete");
    expect(mapTextAction("start")).toBe("start");
    expect(mapTextAction("h")).toBe("help");
    expect(mapTextAction("restart")).toBe("restart");
  });

  it("returns null for unknown values", () => {
    expect(mapTextAction("unknown")).toBeNull();
  });
});
