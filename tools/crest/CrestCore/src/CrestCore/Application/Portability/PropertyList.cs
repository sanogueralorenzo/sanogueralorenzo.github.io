using System.Buffers.Binary;
using System.Text;

namespace CrestCore.Application;

/// A binary property list, as Safari keeps its bookmarks and sessions, read
/// into plain values: a dictionary is `IReadOnlyDictionary<string, object>`
/// in the order the file lists it, an array `IReadOnlyList<object>`, a number
/// `long` or `double`, a flag `bool`, a date `PropertyListDate`, and data
/// `byte[]`. A list that is malformed, refers to itself or nests too deeply
/// reads as nothing.
internal sealed class PropertyList {
    #region Static Variables

    private static readonly byte[] Magic = "bplist00"u8.ToArray();

    private const int TrailerLength = 32;
    /// How deep a list may nest.
    private const int MaximumDepth = 512;
    /// The most values one list reads, counting a value each time it is
    /// referred to, so a list that refers to one value many times cannot grow
    /// without bound.
    private const int MaximumValues = 4_000_000;

    #endregion

    #region Variables

    private readonly byte[] contents;
    private readonly long[] offsets;
    private readonly int referenceSize;
    private readonly HashSet<long> reading = [];
    private int values;

    #endregion

    #region Constructors

    private PropertyList(byte[] contents, long[] offsets, int referenceSize) {
        this.contents = contents;
        this.offsets = offsets;
        this.referenceSize = referenceSize;
    }

    #endregion

    #region Actions - Reading

    /// The value `contents` holds, or null when it is not a binary property
    /// list this reader can read.
    public static object? Read(byte[] contents) {
        ArgumentNullException.ThrowIfNull(contents);
        if (contents.Length < Magic.Length + TrailerLength || !contents.AsSpan(0, Magic.Length).SequenceEqual(Magic)) return null;
        var trailer = contents.AsSpan(contents.Length - TrailerLength);
        int offsetSize = trailer[6], referenceSize = trailer[7];
        ulong count = BinaryPrimitives.ReadUInt64BigEndian(trailer[8..]);
        ulong top = BinaryPrimitives.ReadUInt64BigEndian(trailer[16..]);
        ulong table = BinaryPrimitives.ReadUInt64BigEndian(trailer[24..]);
        if (offsetSize is < 1 or > 8 || referenceSize is < 1 or > 8 || count == 0 || top >= count
            || table >= (ulong)contents.Length || count > (ulong)(contents.Length - (long)table) / (ulong)offsetSize) return null;
        var offsets = new long[count];
        for (ulong index = 0; index < count; index++) {
            ulong offset = Unsigned(contents.AsSpan((int)(table + index * (ulong)offsetSize), offsetSize));
            if (offset >= table) return null;
            offsets[index] = (long)offset;
        }
        try {
            return new PropertyList(contents, offsets, referenceSize).Object((long)top, depth: 0);
        } catch (FormatException) {
            return null;
        }
    }

    private object Object(long reference, int depth) {
        if (reference < 0 || reference >= offsets.Length || depth > MaximumDepth || ++values > MaximumValues
            || !reading.Add(reference))
            throw new FormatException();
        try {
            return Decoded(offsets[reference], depth);
        } finally {
            reading.Remove(reference);
        }
    }

    private object Decoded(long offset, int depth) {
        byte marker = At(offset);
        int kind = marker >> 4, info = marker & 0xF;
        switch (kind) {
            case 0x0 when info == 0x8:
                return false;
            case 0x0 when info == 0x9:
                return true;
            case 0x1 when info <= 3:
                return Integer(offset + 1, 1 << info);
            case 0x2 when info == 2:
                return (double)BinaryPrimitives.ReadSingleBigEndian(Span(offset + 1, 4));
            case 0x2 when info == 3:
                return BinaryPrimitives.ReadDoubleBigEndian(Span(offset + 1, 8));
            case 0x3 when info == 3:
                return new PropertyListDate(BinaryPrimitives.ReadDoubleBigEndian(Span(offset + 1, 8)));
            case 0x4: {
                    var (length, start) = Length(offset, info);
                    return Span(start, length).ToArray();
                }
            case 0x5: {
                    var (length, start) = Length(offset, info);
                    return Encoding.ASCII.GetString(Span(start, length));
                }
            case 0x6: {
                    var (length, start) = Length(offset, info);
                    return Encoding.BigEndianUnicode.GetString(Span(start, checked(length * 2)));
                }
            case 0xA: {
                    var (length, start) = Length(offset, info);
                    var items = new List<object>(length);
                    for (int index = 0; index < length; index++) items.Add(Object(Reference(start, index), depth + 1));
                    return items;
                }
            case 0xD: {
                    var (length, start) = Length(offset, info);
                    var members = new OrderedDictionary<string, object>(length);
                    for (int index = 0; index < length; index++) {
                        if (Object(Reference(start, index), depth + 1) is not string key) throw new FormatException();
                        members[key] = Object(Reference(start, length + index), depth + 1);
                    }
                    return members;
                }
            default:
                throw new FormatException();
        }
    }

    /// A count that follows a marker: its low bits, or the integer after it.
    private (int Length, long Start) Length(long offset, int info) {
        if (info != 0xF) return (info, offset + 1);
        byte marker = At(offset + 1);
        if (marker >> 4 != 0x1 || (marker & 0xF) > 3) throw new FormatException();
        int size = 1 << (marker & 0xF);
        long length = Integer(offset + 2, size);
        if (length is < 0 or > int.MaxValue) throw new FormatException();
        return ((int)length, offset + 2 + size);
    }

    private long Reference(long start, int index) => (long)Unsigned(Span(start + (long)index * referenceSize, referenceSize));

    private long Integer(long offset, int size) {
        var bytes = Span(offset, size);
        return size == 8 ? BinaryPrimitives.ReadInt64BigEndian(bytes) : (long)Unsigned(bytes);
    }

    private byte At(long offset) => offset >= 0 && offset < contents.Length ? contents[offset] : throw new FormatException();

    private ReadOnlySpan<byte> Span(long offset, int length) =>
        offset >= 0 && length >= 0 && offset + length <= contents.Length ? contents.AsSpan((int)offset, length) : throw new FormatException();

    private static ulong Unsigned(ReadOnlySpan<byte> bytes) {
        ulong value = 0;
        foreach (byte part in bytes) value = (value << 8) | part;
        return value;
    }

    #endregion
}
