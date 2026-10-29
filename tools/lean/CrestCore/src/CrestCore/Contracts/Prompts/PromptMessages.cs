namespace CrestCore.Contracts;

/// A quit confirmation no longer waits for an answer.
public sealed record PromptSettled(Guid PromptId) : Change;

/// The quit confirmation no longer waits.
public sealed record UnknownPrompt(Guid PromptId) : Rejection;
