using CrestCore.Domain;

namespace CrestCore.Tests;

/// Fresh identities, except that the next one the thread that asked draws
/// waits until the test resumes it, holding that thread where it draws.
internal sealed class PausingIds : IIdSource {
    #region Variables

    private readonly TaskCompletionSource paused = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly ManualResetEventSlim resumed = new();
    private int pausing = -1;

    /// Finishes once the paused thread waits.
    public Task Paused => paused.Task;

    #endregion

    #region Actions - Pausing

    /// The next identity this thread draws waits until `Resume`.
    public void PauseNextDraw() => Volatile.Write(ref pausing, Environment.CurrentManagedThreadId);

    public void Resume() => resumed.Set();

    #endregion

    #region Actions - Identity supply

    public Guid Next() {
        int thread = Environment.CurrentManagedThreadId;
        if (Interlocked.CompareExchange(ref pausing, -1, thread) == thread) {
            paused.SetResult();
            resumed.Wait();
        }
        return Guid.NewGuid();
    }

    #endregion
}
