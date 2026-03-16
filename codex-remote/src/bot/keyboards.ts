import { Keyboard } from "grammy";

export const BUTTON_NEW = "New Chat";
export const BUTTON_RESUME = "Resume Chat";
export const BUTTON_DELETE = "Delete Chat";

const APPROVAL_ACCEPT = "Accept";
const APPROVAL_ACCEPT_SESSION = "Accept Session";
const APPROVAL_DECLINE = "Decline";
const APPROVAL_CANCEL = "Cancel";

const APPROVAL_DECISION_BY_TEXT: Record<string, "accept" | "acceptForSession" | "decline" | "cancel"> = {
  [APPROVAL_ACCEPT.toLowerCase()]: "accept",
  [APPROVAL_ACCEPT_SESSION.toLowerCase()]: "acceptForSession",
  [APPROVAL_DECLINE.toLowerCase()]: "decline",
  [APPROVAL_CANCEL.toLowerCase()]: "cancel"
};

export function quickActionsKeyboard(): Keyboard {
  return new Keyboard()
    .text(BUTTON_NEW)
    .row()
    .text(BUTTON_RESUME)
    .row()
    .text(BUTTON_DELETE)
    .resized()
    .persistent();
}

export function approvalKeyboard(): Keyboard {
  return new Keyboard()
    .text(APPROVAL_ACCEPT)
    .row()
    .text(APPROVAL_ACCEPT_SESSION)
    .row()
    .text(APPROVAL_DECLINE)
    .row()
    .text(APPROVAL_CANCEL)
    .resized()
    .oneTime();
}

export function threadSelectionKeyboard(
  threadTitles: string[],
  options: { includeNewButton?: boolean } = {}
): Keyboard {
  const keyboard = new Keyboard();
  if (options.includeNewButton ?? true) {
    keyboard.text(BUTTON_NEW).row();
  }

  const labels = buildThreadSelectionLabels(threadTitles);
  for (const label of labels) {
    keyboard.text(label).row();
  }

  return keyboard.resized().oneTime();
}

export function newFolderSelectionKeyboard(folderLabels: string[]): Keyboard {
  const keyboard = new Keyboard();
  const labels = buildFolderSelectionLabels(folderLabels);
  labels.forEach((label) => {
    keyboard.text(label).row();
  });
  return keyboard.resized().oneTime();
}

export function buildThreadSelectionLabels(threadTitles: string[]): string[] {
  return threadTitles.map((title, idx) => formatIndexedButtonLabel(idx + 1, title));
}

export function buildFolderSelectionLabels(folderLabels: string[]): string[] {
  return folderLabels.map((label, idx) => formatIndexedButtonLabel(idx + 1, label));
}

export function parseSelectionFromOptions(text: string, optionLabels: string[]): number | null {
  const trimmed = text.trim();
  if (!trimmed) {
    return null;
  }

  const explicitIndex = parseStandaloneSelectionIndex(trimmed);
  if (explicitIndex !== null && explicitIndex >= 1 && explicitIndex <= optionLabels.length) {
    return explicitIndex;
  }

  const normalized = normalizeForComparison(trimmed);
  for (let idx = 0; idx < optionLabels.length; idx += 1) {
    if (normalized === normalizeForComparison(optionLabels[idx])) {
      return idx + 1;
    }
  }

  return null;
}

export function parseApprovalDecisionText(
  text: string
): "accept" | "acceptForSession" | "decline" | "cancel" | null {
  const normalized = text.trim().toLowerCase();
  return APPROVAL_DECISION_BY_TEXT[normalized] ?? null;
}

function formatIndexedButtonLabel(index: number, label: string): string {
  return `${index}. ${label}`;
}

function parseStandaloneSelectionIndex(text: string): number | null {
  const match = text.match(/^(\d+)\.?$/);
  if (!match) {
    return null;
  }

  const parsed = Number.parseInt(match[1], 10);
  if (!Number.isFinite(parsed)) {
    return null;
  }

  return parsed;
}

function normalizeForComparison(text: string): string {
  return text.trim().replace(/\s+/g, " ");
}
