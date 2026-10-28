using System.Buffers;
using System.Buffers.Binary;
using System.Text;

namespace CrestCore.Native;

/// Writes the positional contract wire format that `WireReader` reads.
public sealed class WireWriter {
    #region Variables

    private readonly ArrayBufferWriter<byte> buffer = new();

    public ReadOnlySpan<byte> WrittenSpan => buffer.WrittenSpan;

    #endregion

    #region Actions - Clearing

    /// Zeroes what was written and starts over.
    public void Clear() => buffer.Clear();

    #endregion

    #region Actions - Structure

    public void WriteTag(int tag) => WriteVarint(checked((ulong)tag));

    public void WriteCount(int count) => WriteVarint(checked((ulong)count));

    public void WritePresence(bool isPresent) => WriteBool(isPresent);

    public void WriteEnum(int value) => WriteVarint(checked((ulong)value));

    public void WriteVarint(ulong value) {
        var span = buffer.GetSpan(10);
        int length = 0;
        do {
            byte next = (byte)(value & 0x7f);
            value >>= 7;
            span[length++] = value == 0 ? next : (byte)(next | 0x80);
        } while (value != 0);
        buffer.Advance(length);
    }

    #endregion

    #region Actions - Values

    public void WriteBool(bool value) {
        buffer.GetSpan(1)[0] = value ? (byte)1 : (byte)0;
        buffer.Advance(1);
    }

    public void WriteInt32(int value) {
        BinaryPrimitives.WriteInt32LittleEndian(buffer.GetSpan(4), value);
        buffer.Advance(4);
    }

    public void WriteInt64(long value) {
        BinaryPrimitives.WriteInt64LittleEndian(buffer.GetSpan(8), value);
        buffer.Advance(8);
    }

    public void WriteUInt64(ulong value) {
        BinaryPrimitives.WriteUInt64LittleEndian(buffer.GetSpan(8), value);
        buffer.Advance(8);
    }

    public void WriteDouble(double value) {
        BinaryPrimitives.WriteDoubleLittleEndian(buffer.GetSpan(8), value);
        buffer.Advance(8);
    }

    public void WriteString(string value) {
        ArgumentNullException.ThrowIfNull(value);
        int length = Encoding.UTF8.GetByteCount(value);
        WriteCount(length);
        Encoding.UTF8.GetBytes(value, buffer.GetSpan(length));
        buffer.Advance(length);
    }

    public void WriteBytes(byte[] value) {
        ArgumentNullException.ThrowIfNull(value);
        WriteCount(value.Length);
        value.CopyTo(buffer.GetSpan(value.Length));
        buffer.Advance(value.Length);
    }

    public void WriteGuid(Guid value) {
        if (!value.TryWriteBytes(buffer.GetSpan(16), bigEndian: true, out int written) || written != 16)
            throw new InvalidOperationException("A GUID did not write 16 bytes.");
        buffer.Advance(16);
    }

    public void WriteDate(DateTimeOffset value) => WriteDouble(Seconds((value - WireReader.ReferenceDate).Ticks));

    public void WriteDuration(TimeSpan value) => WriteDouble(Seconds(value.Ticks));

    private static double Seconds(long ticks) => ticks / (double)TimeSpan.TicksPerSecond;

    #endregion
}
