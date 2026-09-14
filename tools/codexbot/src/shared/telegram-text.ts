const TELEGRAM_MESSAGE_LIMIT = 4096;
const TELEGRAM_MESSAGE_CHUNK = 3900;

export async function sendTextChunks(
  sender: (text: string) => Promise<unknown>,
  text: string
): Promise<void> {
  const chunks = splitTextForTelegram(text);
  for (const chunk of chunks) {
    await sender(chunk);
  }
}

function splitTextForTelegram(text: string, maxLen = TELEGRAM_MESSAGE_CHUNK): string[] {
  if (text.length <= TELEGRAM_MESSAGE_LIMIT) {
    return [text];
  }

  const chunks: string[] = [];
  let remaining = text;
  while (remaining.length > maxLen) {
    let splitAt = remaining.lastIndexOf("\n", maxLen);
    if (splitAt < Math.floor(maxLen * 0.5)) {
      splitAt = remaining.lastIndexOf(" ", maxLen);
    }
    if (splitAt <= 0) {
      splitAt = maxLen;
    }

    const head = remaining.slice(0, splitAt).trimEnd();
    if (head) {
      chunks.push(head);
    }
    remaining = remaining.slice(splitAt).trimStart();
  }

  if (remaining) {
    chunks.push(remaining);
  }

  return chunks.length ? chunks : [""];
}
