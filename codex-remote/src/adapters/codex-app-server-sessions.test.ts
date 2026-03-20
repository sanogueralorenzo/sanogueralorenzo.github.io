import { describe, expect, it } from "vitest";
import { ListedSession, sortSessionsByLastUpdatedDesc } from "./codex-app-server-sessions.js";

describe("sortSessionsByLastUpdatedDesc", () => {
  it("orders sessions by latest updated timestamp first", () => {
    const sessions: ListedSession[] = [
      {
        id: "old",
        title: "Old",
        folder: "repo",
        cwd: "/tmp/repo",
        lastUpdatedAt: "2026-03-10T10:00:00Z",
      },
      {
        id: "new",
        title: "New",
        folder: "repo",
        cwd: "/tmp/repo",
        lastUpdatedAt: "2026-03-12T10:00:00Z",
      },
      {
        id: "middle",
        title: "Middle",
        folder: "repo",
        cwd: "/tmp/repo",
        lastUpdatedAt: "2026-03-11T10:00:00Z",
      },
    ];

    expect(sortSessionsByLastUpdatedDesc(sessions).map((session) => session.id)).toEqual([
      "new",
      "middle",
      "old",
    ]);
  });

  it("keeps original order for invalid or tied timestamps", () => {
    const sessions: ListedSession[] = [
      {
        id: "a",
        title: "A",
        folder: "repo",
        cwd: "/tmp/repo",
        lastUpdatedAt: "not-a-date",
      },
      {
        id: "b",
        title: "B",
        folder: "repo",
        cwd: "/tmp/repo",
        lastUpdatedAt: "not-a-date",
      },
    ];

    expect(sortSessionsByLastUpdatedDesc(sessions).map((session) => session.id)).toEqual(["a", "b"]);
  });
});
