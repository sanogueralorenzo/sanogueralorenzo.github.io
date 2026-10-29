import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Agent } from "./agent.ts";
import { createAgentServer } from "./http-server.ts";

const workspace = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const app = await Agent.open(join(homedir(), ".agent"), workspace);
const { server, close } = createAgentServer(app);
server.listen(4180, "127.0.0.1", () => console.log("Agent is available at http://127.0.0.1:4180"));
for (const signal of ["SIGINT", "SIGTERM"] as const) process.once(signal, () => {
  void close().then(() => app.shutdown()).then(() => process.exit(0));
});
