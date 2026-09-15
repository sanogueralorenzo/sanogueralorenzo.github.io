import { Keyboard } from "grammy";

export const BUTTON_NEW = "New Topic";
export const BUTTON_ARCHIVE = "Archive Topic";

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
    .text(BUTTON_ARCHIVE)
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

export function parseApprovalDecisionText(
  text: string
): "accept" | "acceptForSession" | "decline" | "cancel" | null {
  const normalized = text.trim().toLowerCase();
  return APPROVAL_DECISION_BY_TEXT[normalized] ?? null;
}
