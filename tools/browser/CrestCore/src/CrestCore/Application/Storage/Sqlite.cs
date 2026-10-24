using System.Reflection;
using System.Runtime.InteropServices;

namespace CrestCore.Application;

/// The system SQLite library. NativeAOT links it directly (`DirectPInvoke` in
/// the native project); a JIT host resolves it by the names each platform ships.
internal static partial class Sqlite {
    #region Variables

    private const string Library = "libsqlite3";

    public const int Ok = 0, Row = 100, Done = 101;
    /// `SQLITE_NULL`, the type of a column that holds no value.
    private const int Null = 5;
    public const int OpenReadOnly = 0x1, OpenReadWrite = 0x2, OpenCreate = 0x4, OpenUri = 0x40, OpenFullMutex = 0x10000;

    /// `SQLITE_TRANSIENT`: SQLite copies bound values before the call returns.
    private static readonly nint Transient = -1;

    /// Where a JIT host finds the library: macOS, then the Linux soname CI has.
    private static readonly string[] JitLibraryNames = ["libsqlite3.dylib", "/usr/lib/libsqlite3.dylib", "libsqlite3.so.0", "libsqlite3.so"];

    #endregion

    #region Constructors

    static Sqlite() => NativeLibrary.SetDllImportResolver(typeof(Sqlite).Assembly, Resolve);

    #endregion

    #region Actions - Loading

    private static nint Resolve(string name, Assembly assembly, DllImportSearchPath? searchPath) {
        if (name != Library) return 0;
        foreach (var candidate in JitLibraryNames)
            if (NativeLibrary.TryLoad(candidate, out var handle)) return handle;
        return 0;
    }

    #endregion

    #region Actions - Binding


    public static unsafe int BindBlob(nint statement, int index, ReadOnlySpan<byte> value) {
        fixed (byte* bytes = value) return sqlite3_bind_blob(statement, index, bytes, value.Length, Transient);
    }

    /// The column's bytes, copied out before the statement moves on.
    public static unsafe byte[] ColumnBlob(nint statement, int column) {
        int count = sqlite3_column_bytes(statement, column);
        var source = sqlite3_column_blob(statement, column);
        return count == 0 || source == null ? [] : new ReadOnlySpan<byte>(source, count).ToArray();
    }

    public static int BindNull(nint statement, int index) => sqlite3_bind_null(statement, index);

    public static int BindText(nint statement, int index, string? value) =>
        value is null ? sqlite3_bind_null(statement, index) : sqlite3_bind_text(statement, index, value, -1, Transient);

    /// Whether a column holds SQL NULL.
    public static bool ColumnIsNull(nint statement, int column) => sqlite3_column_type(statement, column) == Null;

    public static string ColumnText(nint statement, int column) =>
        Marshal.PtrToStringUTF8(sqlite3_column_text(statement, column)) ?? "";

    public static string Message(nint connection) => Marshal.PtrToStringUTF8(sqlite3_errmsg(connection)) ?? "";

    #endregion

    #region Actions - Library

    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    public static partial int sqlite3_open_v2(string filename, out nint connection, int flags, string? vfs);

    [LibraryImport(Library)]
    public static partial int sqlite3_close_v2(nint connection);

    [LibraryImport(Library)]
    public static partial int sqlite3_busy_timeout(nint connection, int milliseconds);

    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    public static partial int sqlite3_exec(nint connection, string sql, nint callback, nint argument, nint errorMessage);

    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    public static partial int sqlite3_prepare_v2(nint connection, string sql, int length, out nint statement, nint tail);

    [LibraryImport(Library)]
    public static partial int sqlite3_step(nint statement);

    [LibraryImport(Library)]
    public static partial int sqlite3_finalize(nint statement);

    [LibraryImport(Library)]
    public static partial int sqlite3_column_int(nint statement, int column);

    [LibraryImport(Library)]
    public static partial long sqlite3_column_int64(nint statement, int column);

    [LibraryImport(Library)]
    public static partial double sqlite3_column_double(nint statement, int column);

    [LibraryImport(Library)]
    public static partial int sqlite3_bind_int64(nint statement, int index, long value);

    [LibraryImport(Library)]
    public static partial int sqlite3_bind_double(nint statement, int index, double value);

    [LibraryImport(Library)]
    private static partial int sqlite3_bind_null(nint statement, int index);

    [LibraryImport(Library)]
    private static partial int sqlite3_column_type(nint statement, int column);

    [LibraryImport(Library)]
    public static partial int sqlite3_extended_errcode(nint connection);

    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    public static partial nint sqlite3_backup_init(nint destination, string destinationName, nint source, string sourceName);

    [LibraryImport(Library)]
    public static partial int sqlite3_backup_step(nint backup, int pages);

    [LibraryImport(Library)]
    public static partial int sqlite3_backup_finish(nint backup);

    [LibraryImport(Library, StringMarshalling = StringMarshalling.Utf8)]
    private static partial int sqlite3_bind_text(nint statement, int index, string value, int length, nint destructor);

    [LibraryImport(Library)]
    private static unsafe partial int sqlite3_bind_blob(nint statement, int index, byte* value, int length, nint destructor);

    [LibraryImport(Library)]
    private static unsafe partial byte* sqlite3_column_blob(nint statement, int column);

    [LibraryImport(Library)]
    private static partial int sqlite3_column_bytes(nint statement, int column);

    [LibraryImport(Library)]
    private static partial nint sqlite3_column_text(nint statement, int column);

    [LibraryImport(Library)]
    private static partial nint sqlite3_errmsg(nint connection);

    #endregion
}
