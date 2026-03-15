const DEFAULT_TELEGRAM_DRAFT_STREAM_MIN = 200;
const DEFAULT_TELEGRAM_DRAFT_STREAM_MAX = 800;

export type DraftBreakPreference = "paragraph" | "newline" | "sentence";

export function resolveTelegramDraftStreamingChunking(): {
  minChars: number;
  maxChars: number;
  breakPreference: DraftBreakPreference;
} {
  return {
    minChars: DEFAULT_TELEGRAM_DRAFT_STREAM_MIN,
    maxChars: DEFAULT_TELEGRAM_DRAFT_STREAM_MAX,
    breakPreference: "paragraph"
  };
}

