import type { InputFile, Keyboard } from "grammy";

export type ReplyMarkup = Keyboard | { remove_keyboard: true; selective?: boolean };
export type ReplyFn = (text: string, options?: { reply_markup?: ReplyMarkup }) => Promise<unknown>;

export type PromptContext = {
  chat: { id: number };
  api: {
    sendMessage: (chatId: number, text: string, other?: { reply_markup?: ReplyMarkup }) => Promise<unknown>;
    sendPhoto: (chatId: number, photo: InputFile | string) => Promise<unknown>;
    sendChatAction: (chatId: number, action: "typing") => Promise<unknown>;
    getFile: (fileId: string) => Promise<{ file_path?: string }>;
  };
  message: {
    message_thread_id?: number;
    voice?: {
      file_id: string;
    };
  };
  reply: (text: string, options?: { reply_markup?: ReplyMarkup }) => Promise<unknown>;
};
