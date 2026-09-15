import type { InputFile, Keyboard } from "grammy";

export type ReplyMarkup = Keyboard | { remove_keyboard: true; selective?: boolean };
export type ReplyFn = (text: string, options?: { reply_markup?: ReplyMarkup }) => Promise<unknown>;

export type PromptContext = {
  chat: { id: number };
  api: {
    sendMessage: (
      chatId: number,
      text: string,
      other?: { reply_markup?: ReplyMarkup; message_thread_id?: number }
    ) => Promise<unknown>;
    sendPhoto: (
      chatId: number,
      photo: InputFile | string,
      other?: { message_thread_id?: number }
    ) => Promise<unknown>;
    sendChatAction: (
      chatId: number,
      action: "typing",
      other?: { message_thread_id?: number }
    ) => Promise<unknown>;
    getFile: (fileId: string) => Promise<{ file_path?: string }>;
    createForumTopic: (chatId: number, name: string) => Promise<{ message_thread_id: number; name: string }>;
    editForumTopic: (chatId: number, messageThreadId: number, other: { name: string }) => Promise<unknown>;
    closeForumTopic: (chatId: number, messageThreadId: number) => Promise<unknown>;
  };
  message: {
    message_thread_id?: number;
    voice?: {
      file_id: string;
    };
  };
  reply: (text: string, options?: { reply_markup?: ReplyMarkup }) => Promise<unknown>;
};
