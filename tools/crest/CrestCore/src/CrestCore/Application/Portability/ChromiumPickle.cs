using System.Buffers.Binary;
using System.Text;

namespace CrestCore.Application;

/// A Chromium pickle: a little-endian payload size, then values, each padded
/// to four bytes. A value that runs past the payload reads as nothing.
internal ref struct ChromiumPickle {
    #region Variables

    private readonly ReadOnlySpan<byte> contents;
    private readonly int end;
    private int position;

    /// The declared payload fits the bytes.
    public bool IsValid { get; }

    #endregion

    #region Constructors

    /// A pickle over `contents`, or a reader that reads nothing when the
    /// declared size runs past them.
    public ChromiumPickle(ReadOnlySpan<byte> contents) {
        this.contents = contents;
        position = 4;
        IsValid = contents.Length >= 4 && BinaryPrimitives.ReadUInt32LittleEndian(contents) <= (uint)(contents.Length - 4);
        end = IsValid ? 4 + (int)BinaryPrimitives.ReadUInt32LittleEndian(contents) : 0;
    }

    #endregion

    #region Actions - Reading

    public int? Int32() {
        if (position + 4 > contents.Length || position + 4 > end) return null;
        int value = BinaryPrimitives.ReadInt32LittleEndian(contents[position..]);
        position += 4;
        return value;
    }

    public ulong? UInt64() {
        if (position + 8 > contents.Length || position + 8 > end) return null;
        ulong value = BinaryPrimitives.ReadUInt64LittleEndian(contents[position..]);
        position += 8;
        return value;
    }

    /// A UTF-8 string of at most `maximumBytes`.
    public string? Utf8(int maximumBytes) {
        if (Int32() is not { } length || length < 0 || length > maximumBytes || length > end - position) return null;
        string value = Encoding.UTF8.GetString(contents.Slice(position, length));
        position += length;
        return Aligned(value);
    }

    /// A UTF-16 string of at most `maximumUnits` code units.
    public string? Utf16(int maximumUnits) {
        if (Int32() is not { } count || count < 0 || count > maximumUnits) return null;
        long bytes = (long)count * 2;
        if (bytes > end - position) return null;
        string value = Encoding.Unicode.GetString(contents.Slice(position, (int)bytes));
        position += (int)bytes;
        return Aligned(value);
    }

    private string? Aligned(string value) {
        position = (position + 3) & ~3;
        return position <= end ? value : null;
    }

    #endregion
}
