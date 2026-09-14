import { describe, expect, it } from "vitest";
import {
  buildThreadSelectionLabels,
  parseApprovalDecisionText,
  parseSelectionFromOptions
} from "./keyboards.js";

describe("buildThreadSelectionLabels", () => {
  it("uses stable numeric labels", () => {
    expect(buildThreadSelectionLabels(["", "Hello world"])).toEqual(["1", "2"]);
  });
});

describe("parseSelectionFromOptions", () => {
  it("accepts numeric choices and rejects full labels", () => {
    const options = ["1", "2"];
    expect(parseSelectionFromOptions("2", options)).toBe(2);
    expect(parseSelectionFromOptions("1. Alpha", options)).toBeNull();
  });
});

describe("parseApprovalDecisionText", () => {
  it("maps approval labels to decision values", () => {
    expect(parseApprovalDecisionText("Accept")).toBe("accept");
    expect(parseApprovalDecisionText("accept session")).toBe("acceptForSession");
    expect(parseApprovalDecisionText("Decline")).toBe("decline");
    expect(parseApprovalDecisionText("Cancel")).toBe("cancel");
    expect(parseApprovalDecisionText("nope")).toBeNull();
  });
});
