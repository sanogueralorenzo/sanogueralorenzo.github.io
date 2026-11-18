import { defineDoc, defineTool, section } from "@earendil-works/pi-durable";
import { Type } from "typebox";

export const WorkingNotesDoc = defineDoc<{ text: string }>({ kind: "agent.working-notes", version: 1,
  scope: "conversation", history: "latest", fork: "initial", checkpointWhen: () => false, initial: () => ({ text: "" }) });

export const workingNotes = defineTool({ name: "working_notes", replay: "safe", executionMode: "sequential",
  description: "Read or replace your private working notes. Keep a compact record of the goal, constraints, decisions, evidence references, open questions, and next actions when useful. Omit text to read; supply text to replace, or an empty string to clear. Notes persist in this conversation and appear in your context; workers have their own notes.",
  parameters: Type.Object({ text: Type.Optional(Type.String({ maxLength: 6000 })) }, { additionalProperties: false }),
  execute: async (args, api, context) => {
    if (args.text === undefined) {
      const notes = await api.snapshot(WorkingNotesDoc, api.conversationId, context);
      return { output: [{ type: "text", text: notes?.text || "No working notes." }] };
    }
    await api.commit(async tx => { (await tx.doc(WorkingNotesDoc, api.conversationId)).text = args.text!; }, context);
    return { output: [{ type: "text", text: args.text ? "Working notes updated." : "Working notes cleared." }] };
  } });

export const workingNotesSection = section("working_notes", async ({ read, conversationId }, context) => {
  const notes = await read.snapshot(WorkingNotesDoc, conversationId, context);
  return notes?.text || undefined;
});
