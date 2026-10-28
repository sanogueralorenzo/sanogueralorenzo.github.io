namespace CrestCore.Native;

/// Bytes that are not a well-formed contract message. The native entry points
/// answer INVALID_MESSAGE.
public sealed class WireFormatException(string message) : Exception(message);
