export const HELP_TEXT = [
  "Agent Gateway, your remote AI tool",
  "",
  "Tip: Voice notes work!"
].join("\n");

export const THREAD_NOT_BOUND_MESSAGE = "No thread bound.\n\nUse /resume and pick one, or /new.";

export function formatFailure(prefix: string, message: string): string {
  return `${prefix}\n\n${message}`;
}

export function formatActionTitle(action: string, title: string): string {
  return `${action}: ${title}`;
}

export function cleanPreview(text: string): string {
  const oneLine = text.replace(/\s+/g, " ").trim();
  if (!oneLine) {
    return "";
  }
  if (oneLine.length <= 80) {
    return oneLine;
  }
  return `${oneLine.slice(0, 77)}...`;
}

export function formatFolderLabel(folder: string): string {
  const normalized = folder.replace(/[_-]+/g, " ").trim();
  if (!normalized) {
    return "Unknown Folder";
  }

  return normalized
    .split(/\s+/)
    .map((word) => {
      if (!word) {
        return "";
      }
      return `${word[0].toUpperCase()}${word.slice(1)}`;
    })
    .join(" ");
}
