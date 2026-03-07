import { Keyboard } from "grammy";

export const BUTTON_NEW = "New Chat";
export const BUTTON_RESUME = "Resume Chat";
export const BUTTON_DELETE = "Delete Chat";

const APPROVAL_ACCEPT = "Accept";
const APPROVAL_ACCEPT_SESSION = "Accept Session";
const APPROVAL_DECLINE = "Decline";
const APPROVAL_CANCEL = "Cancel";

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
  return threadTitles.map((title, idx) => formatIndexedButtonLabel(idx + 1, formatThreadButtonLabel(title)));
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
  if (normalized === APPROVAL_ACCEPT.toLowerCase()) {
    return "accept";
  }
  if (normalized === APPROVAL_ACCEPT_SESSION.toLowerCase()) {
    return "acceptForSession";
  }
  if (normalized === APPROVAL_DECLINE.toLowerCase()) {
    return "decline";
  }
  if (normalized === APPROVAL_CANCEL.toLowerCase()) {
    return "cancel";
  }
  return null;
}

function formatThreadButtonLabel(title: string): string {
  const oneLine = title.replace(/\s+/g, " ").trim();
  if (!oneLine) {
    return "Untitled";
  }

  const maxLen = 36;
  if (oneLine.length <= maxLen) {
    return oneLine;
  }
  return `${oneLine.slice(0, maxLen - 3)}...`;
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
