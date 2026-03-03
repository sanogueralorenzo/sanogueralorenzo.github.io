import { Keyboard } from "grammy";

export type ReplyFn = (text: string, options?: { reply_markup?: Keyboard }) => Promise<unknown>;

export type PromptContext = {
  chat: { id: number };
  api: {
    sendMessage: (chatId: number, text: string, other?: { reply_markup?: Keyboard }) => Promise<unknown>;
    sendMessageDraft: (
      chatId: number,
      draftId: number,
      text: string,
      other?: { message_thread_id?: number }
    ) => Promise<true>;
    sendChatAction: (chatId: number, action: "typing") => Promise<unknown>;
    getFile: (fileId: string) => Promise<{ file_path?: string }>;
  };
  message: {
    message_thread_id?: number;
    voice?: {
      file_id: string;
    };
  };
  reply: (text: string, options?: { reply_markup?: Keyboard }) => Promise<unknown>;
  replyWithDraft: (text: string, other?: { message_thread_id?: number }) => Promise<true>;
};
