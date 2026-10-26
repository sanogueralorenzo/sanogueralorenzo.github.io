using CrestCore.Application;

namespace CrestCore.Contracts;

/// The server a credential prompt names: its host, port and scheme. The host
/// may be empty.
public sealed record AuthenticationSource(string Host, int Port, string? Scheme) : StandaloneQuery<AuthenticationSourceLabel> {
    #region Variables

    /// The server as the prompt names it: the host, with the port only when it
    /// is not the scheme's default. Null when the challenge has no host; the
    /// platform then names Crest itself.
    internal string? Label {
        get {
            ArgumentNullException.ThrowIfNull(Host);
            if (Host.Length == 0) return null;
            return WebScheme.Spelled(Scheme)?.DefaultPort == Port ? Host : $"{Host}:{Port}";
        }
    }

    #endregion

    #region Actions - Answering

    internal override AuthenticationSourceLabel Answer(StandaloneContext context) => new(Label);

    #endregion
}
