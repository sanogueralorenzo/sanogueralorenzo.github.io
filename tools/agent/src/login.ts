import { login } from "./providers-cli.ts";

try { await login(process.argv.slice(2)); }
catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = error instanceof Error && error.name === "AbortError" ? 130 : 1;
}
