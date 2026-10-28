using System.Buffers.Binary;
using System.Text;

namespace CrestCore.Native;

/// Reads the positional contract wire format. Lengths, counts, tags and enums
/// are LEB128 varints; numbers are fixed-width little-endian; strings and
/// byte strings are a length followed by their bytes; a GUID is 16
/// bytes in RFC 4122 order; dates and durations are f64 seconds, dates since
/// 1 January 2001. Every length is checked against the bytes that remain, and
/// anything malformed throws `WireFormatException`.
public sealed class WireReader(ReadOnlyMemory<byte> bytes) {
    #region Variables

    public static readonly DateTimeOffset ReferenceDate = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    /// The most bytes a union's tag takes: a varint of at most 31 bits.
    public const int MaximumTagBytes = 5;

    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    private int position;

    public int Remaining => bytes.Length - position;

    #endregion

    #region Actions - Structure

    /// A union's tag.
    public int ReadTag() => checked((int)ReadBounded(int.MaxValue, "tag"));

    /// The tag a message starts with, read without consuming anything, or -1
    /// when its first bytes are not a tag.
    public static int PeekTag(ReadOnlySpan<byte> prefix) {
        try {
            return new WireReader(prefix.ToArray()).ReadTag();
        } catch (Exception error) when (error is WireFormatException or OverflowException) {
            return -1;
        }
    }

    /// A list's count. Every element occupies at least one byte.
    public int ReadCount() => checked((int)ReadBounded((ulong)Remaining, "count"));

    /// A list, which nothing can change once it is read.
    public IReadOnlyList<T> ReadList<T>(Func<T> readElement) {
        ArgumentNullException.ThrowIfNull(readElement);
        var items = new T[ReadCount()];
        for (int index = 0; index < items.Length; index++) items[index] = readElement();
        return Array.AsReadOnly(items);
    }

    /// An optional's presence byte.
    public bool ReadPresence() => ReadFlag("presence");

    /// A plain enum's value, which must be below `count`.
    public int ReadEnum(int count) => checked((int)ReadBounded((ulong)count - 1, "enum"));

    /// A flags enum's value, which may only set bits in `mask`.
    public int ReadFlags(int mask) {
        int value = checked((int)ReadBounded(int.MaxValue, "flags"));
        return (value & ~mask) == 0 ? value : throw new WireFormatException($"Unknown flags {value}.");
    }

    public void EnsureEnd() {
        if (Remaining != 0) throw new WireFormatException($"{Remaining} unexpected trailing bytes.");
    }

    public ulong ReadVarint() {
        ulong value = 0;
        for (int shift = 0; shift < 64; shift += 7) {
            byte next = Take(1)[0];
            ulong bits = (ulong)(next & 0x7f);
            if (shift == 63 && bits > 1) throw new WireFormatException("Varint overflow.");
            value |= bits << shift;
            if ((next & 0x80) == 0) {
                if (next == 0 && shift > 0) throw new WireFormatException("Overlong varint.");
                return value;
            }
        }
        throw new WireFormatException("Varint overflow.");
    }

    private ulong ReadBounded(ulong maximum, string what) {
        ulong value = ReadVarint();
        return value <= maximum ? value : throw new WireFormatException($"The {what} {value} exceeds {maximum}.");
    }

    private ReadOnlySpan<byte> Take(int length) {
        if (length > Remaining) throw new WireFormatException("Truncated message.");
        var span = bytes.Span.Slice(position, length);
        position += length;
        return span;
    }

    #endregion

    #region Actions - Values

    public bool ReadBool() => ReadFlag("bool");

    public int ReadInt32() => BinaryPrimitives.ReadInt32LittleEndian(Take(4));

    public long ReadInt64() => BinaryPrimitives.ReadInt64LittleEndian(Take(8));

    public ulong ReadUInt64() => BinaryPrimitives.ReadUInt64LittleEndian(Take(8));

    public double ReadDouble() => BinaryPrimitives.ReadDoubleLittleEndian(Take(8));

    public string ReadString() {
        int length = checked((int)ReadBounded((ulong)Remaining, "string length"));
        try {
            return StrictUtf8.GetString(Take(length));
        } catch (DecoderFallbackException) {
            throw new WireFormatException("A string is not UTF-8.");
        }
    }

    /// A byte string: its length, then the bytes as they are.
    public byte[] ReadBytes() => Take(checked((int)ReadBounded((ulong)Remaining, "byte length"))).ToArray();

    public Guid ReadGuid() => new(Take(16), bigEndian: true);

    public DateTimeOffset ReadDate() {
        long ticks = Ticks(ReadDouble(), "date");
        try {
            return ReferenceDate.AddTicks(ticks);
        } catch (ArgumentOutOfRangeException) {
            throw new WireFormatException("A date is out of range.");
        }
    }

    public TimeSpan ReadDuration() => TimeSpan.FromTicks(Ticks(ReadDouble(), "duration"));

    private bool ReadFlag(string what) => Take(1)[0] switch {
        0 => false,
        1 => true,
        var value => throw new WireFormatException($"A {what} byte is {value}.")
    };

    private static long Ticks(double seconds, string what) {
        double ticks = Math.Round(seconds * TimeSpan.TicksPerSecond);
        return double.IsFinite(ticks) && Math.Abs(ticks) < long.MaxValue
            ? (long)ticks
            : throw new WireFormatException($"A {what} of {seconds} seconds is out of range.");
    }

    #endregion
}
