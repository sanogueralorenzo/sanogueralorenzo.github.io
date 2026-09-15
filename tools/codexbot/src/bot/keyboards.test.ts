import { describe, expect, it } from "vitest";
import { parseApprovalDecisionText } from "./keyboards.js";

describe("parseApprovalDecisionText", () => {
  it("maps approval labels to decision values", () => {
    expect(parseApprovalDecisionText("Accept")).toBe("accept");
    expect(parseApprovalDecisionText("accept session")).toBe("acceptForSession");
    expect(parseApprovalDecisionText("Decline")).toBe("decline");
    expect(parseApprovalDecisionText("Cancel")).toBe("cancel");
    expect(parseApprovalDecisionText("nope")).toBeNull();
  });
});
