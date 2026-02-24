import { Keyboard } from "grammy";

export type ReplyFn = (text: string, options?: { reply_markup?: Keyboard }) => Promise<unknown>;

export type PromptContext = {
  chat: { id: number };
  api: {
    sendMessage: (chatId: number, text: string, other?: { reply_markup?: Keyboard }) => Promise<unknown>;
    sendChatAction: (chatId: number, action: "typing") => Promise<unknown>;
    getFile: (fileId: string) => Promise<{ file_path?: string }>;
  };
  message: {
    voice?: {
      file_id: string;
    };
  };
  reply: (text: string, options?: { reply_markup?: Keyboard }) => Promise<unknown>;
};
