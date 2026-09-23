#!/usr/bin/env node
const args = process.argv.slice(2);
const value = (flag) => args[args.indexOf(flag) + 1];
const prompt = args.at(-1) || "";
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const say = (text, stopReason = "stop") => process.stdout.write(`${JSON.stringify({
  type: "message_end", message: { role: "assistant", content: [{ type: "text", text }], stopReason },
})}\n`);

if (args.includes("--system-prompt")) {
  const role = value("--system-prompt");
  if (role.endsWith("coordinator.md")) {
    if (prompt.includes("SLOW_ROUTE")) await sleep(800);
    const request = prompt.split("User request (verbatim):\n")[1]?.split("\n\nCurrent directory:")[0] || prompt;
    say(JSON.stringify({ routes: [{ agent: "worker", title: "Fake task", task: request }] }));
  } else {
    say(prompt.split("Current child event (authoritative quoted data):\n")[1]?.trim() || "No result");
  }
} else {
  if (prompt.includes("PROGRESS")) say("The worker is now making meaningful progress.", "toolUse");
  if (prompt.includes("SLOW_WORKER")) await sleep(1200);
  else await sleep(100);
  const answer = prompt.match(/ANSWER_[A-Z0-9_]+/)?.[0] || "DONE";
  say(answer);
}
process.stdout.write(`${JSON.stringify({ type: "agent_settled" })}\n`);
