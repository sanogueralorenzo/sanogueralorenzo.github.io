import { describe, expect, it } from "vitest";
import {
  buildThreadSelectionLabels,
  parseApprovalDecisionText,
  parseSelectionFromOptions
} from "./keyboards.js";

describe("buildThreadSelectionLabels", () => {
  it("keeps the title unchanged", () => {
    expect(buildThreadSelectionLabels(["", "Hello world"])).toEqual(["1. ", "2. Hello world"]);
  });
});

describe("parseSelectionFromOptions", () => {
  it("accepts index and full label", () => {
    const options = ["1. Alpha", "2. Beta"];
    expect(parseSelectionFromOptions("2", options)).toBe(2);
    expect(parseSelectionFromOptions("1. Alpha", options)).toBe(1);
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
