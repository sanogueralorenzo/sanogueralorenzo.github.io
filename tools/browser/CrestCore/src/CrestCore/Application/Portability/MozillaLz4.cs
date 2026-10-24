using System.Buffers.Binary;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// Firefox's and Zen's compressed JSON: `mozLz40\0`, the decoded size as a
/// little-endian 32-bit integer, then one raw LZ4 block. A file without the
/// header is plain JSON.
internal static class MozillaLz4 {
    #region Static Variables

    /// The largest JSON a session decodes to.
    public const int MaximumDecodedBytes = BrowserDataFile.MaximumBytes;

    private static readonly byte[] Magic = "mozLz40\0"u8.ToArray();
    private const int HeaderLength = 12;

    #endregion

    #region Actions - Decoding

    /// The JSON `contents` holds. Throws `Rejected` with `SessionOverLimits`
    /// for JSON larger than a session decodes to, and `SessionUnrecognized`
    /// for a block that does not decode to the size its header names.
    public static byte[] Decoded(byte[] contents) {
        ArgumentNullException.ThrowIfNull(contents);
        if (!contents.AsSpan().StartsWith(Magic))
            return contents.Length <= MaximumDecodedBytes ? contents : throw new Rejected(new SessionOverLimits());
        if (contents.Length <= HeaderLength) throw new Rejected(new SessionOverLimits());
        uint size = BinaryPrimitives.ReadUInt32LittleEndian(contents.AsSpan(8, 4));
        if (size is 0 or > MaximumDecodedBytes) throw new Rejected(new SessionOverLimits());
        var output = new byte[size];
        return Block(contents.AsSpan(HeaderLength), output) == output.Length ? output : throw new Rejected(new SessionUnrecognized());
    }

    /// Decodes one raw LZ4 block into `output`, stopping when it is full, and
    /// answers how many bytes it wrote, or -1 for a malformed block.
    private static int Block(ReadOnlySpan<byte> input, Span<byte> output) {
        int read = 0, written = 0;
        while (read < input.Length) {
            byte token = input[read++];
            int literals = token >> 4;
            if (literals == 15 && !TryExtend(input, ref read, ref literals)) return -1;
            if (literals > input.Length - read) return -1;
            int copied = Math.Min(literals, output.Length - written);
            input.Slice(read, copied).CopyTo(output[written..]);
            read += literals;
            written += copied;
            if (written == output.Length || read == input.Length) return written;
            if (input.Length - read < 2) return -1;
            int offset = BinaryPrimitives.ReadUInt16LittleEndian(input[read..]);
            read += 2;
            if (offset == 0 || offset > written) return -1;
            int match = token & 0xF;
            if (match == 15 && !TryExtend(input, ref read, ref match)) return -1;
            match += 4;
            for (int index = 0; index < match && written < output.Length; index++, written++) output[written] = output[written - offset];
            if (written == output.Length) return written;
        }
        return written;
    }

    /// Adds the bytes that extend a length of 15, each 255 meaning more follow.
    private static bool TryExtend(ReadOnlySpan<byte> input, ref int read, ref int length) {
        byte next;
        do {
            if (read >= input.Length) return false;
            next = input[read++];
            if (length > int.MaxValue - next) return false;
            length += next;
        } while (next == 255);
        return true;
    }

    #endregion
}
