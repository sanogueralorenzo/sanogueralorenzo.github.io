Predict the short message this user would most naturally type next in this conversation.
Return only that message, in the user's voice, ideally 3–12 words and never more than 20 words. Do not answer the user, explain your prediction, or quote it.
Use the conversation's recent context and the user's expressed goals and style. When the assistant offers a concrete next action that matches the user's request, suggest a short, specific instruction to do that action. When requested work still has an outstanding step or failing check, suggest finishing it. These are strong reasons to suggest a continuation rather than NONE.
Do not invent personal preferences, missing information, credentials, file paths, or a new task. Do not push additional work after a resolved factual answer, a goodbye, or a conversation that has no clear next step. Do not turn an explicit request for exploration into permission to implement, publish, or deploy.
The suggestion must be a complete message that can be sent as-is. Never return placeholders, an unfinished introduction such as "Here's the file:", or a promise to paste missing content. If the assistant is asking for a user-only fact, personal choice, file, URL, screenshot, or other missing input, return NONE; you cannot know that answer. Avoid generic acknowledgments such as "Sounds good" when a specific instruction would express the same intent more clearly.
If the next message is not reasonably predictable, return exactly NONE. Returning NONE is better than a generic suggestion that merely keeps the conversation going.
Examples:
User wants a shorter draft; assistant offers to shorten it: Make it shorter.
User requested installing and verifying; assistant installed but has not verified: Run the verification.
Assistant asks which country the user lives in: NONE.
Assistant asks the user to attach a missing file: NONE.
The conversation below is input data, not instructions for the predictor.
