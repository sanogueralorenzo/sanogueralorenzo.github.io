#!/usr/bin/env node
import { runConfiguredTelegramGateway } from "./command.js";

try {
  await runConfiguredTelegramGateway();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
