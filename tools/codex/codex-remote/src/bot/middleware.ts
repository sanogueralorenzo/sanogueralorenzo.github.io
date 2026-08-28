const chatLocks = new Map<string, Promise<unknown>>();

export async function withActionErrorBoundary(
  work: () => Promise<void>,
  onError: (message: string) => Promise<unknown>
): Promise<void> {
  try {
    await work();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await onError(message);
  }
}

export async function withChatLock<T>(chatId: string, work: () => Promise<T>): Promise<T> {
  const previous = chatLocks.get(chatId) ?? Promise.resolve();
  const current = previous.then(async () => work());
  const safeCurrent = current.catch(() => undefined);
  chatLocks.set(chatId, safeCurrent);

  try {
    return await current;
  } finally {
    if (chatLocks.get(chatId) === safeCurrent) {
      chatLocks.delete(chatId);
    }
  }
}
