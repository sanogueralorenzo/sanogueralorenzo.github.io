using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

/// Drives the `crest_app_*` exports through bytes, as a native caller does.
internal sealed unsafe class AppClient : IDisposable {
    #region Variables

    public ulong Handle { get; }

    #endregion

    #region Constructors

    /// An app over `storageDirectory`, or in memory without one.
    public AppClient(string? storageDirectory = null) {
        ulong handle = 0;
        var (status, rejection) = Create(ContractCodec.Fingerprint, new AppConfiguration(storageDirectory, DevicePlatform.Desktop), &handle);
        Assert.Null(rejection);
        Assert.Equal(CoreStatus.Ok, status);
        Handle = handle;
    }

    #endregion

    #region Actions - Lifecycle

    /// Creates a memory-only app.
    public static int Create(ReadOnlySpan<byte> fingerprint, ulong* handle) =>
        Create(fingerprint, new AppConfiguration(null, DevicePlatform.Desktop), handle).Status;

    /// Creates an app and answers the rejection it refused with, if any.
    public static (int Status, Rejection? Rejection) Create(ReadOnlySpan<byte> fingerprint, AppConfiguration configuration, ulong* handle) {
        var encoded = Encode(writer => ContractCodec.WriteAppConfiguration(writer, configuration));
        CrestBuffer buffer;
        int status;
        fixed (byte* bytes = fingerprint)
        fixed (byte* settings = encoded)
            status = ((delegate* unmanaged[Cdecl]<byte*, nuint, byte*, nuint, ulong*, CrestBuffer*, int>)&Exports.AppCreate)(
                bytes, (nuint)fingerprint.Length, settings, (nuint)encoded.Length, handle, &buffer);
        Rejection? rejection = null;
        if (buffer.Bytes != null) {
            var reader = new WireReader(new ReadOnlySpan<byte>(buffer.Bytes, (int)buffer.Length).ToArray());
            rejection = ContractCodec.ReadRejection(reader);
            reader.EnsureEnd();
        }
        ((delegate* unmanaged[Cdecl]<CrestBuffer*, void>)&Exports.BufferFree)(&buffer);
        return (status, rejection);
    }

    /// Restores the recovery checkpoint in `configuration`'s directory and
    /// answers the rejection it refused with, if any.
    public static (int Status, Rejection? Rejection) Restore(AppConfiguration configuration) {
        var fingerprint = ContractCodec.Fingerprint;
        var encoded = Encode(writer => ContractCodec.WriteAppConfiguration(writer, configuration));
        CrestBuffer buffer;
        int status;
        fixed (byte* bytes = fingerprint)
        fixed (byte* settings = encoded)
            status = ((delegate* unmanaged[Cdecl]<byte*, nuint, byte*, nuint, CrestBuffer*, int>)&Exports.AppRestore)(
                bytes, (nuint)fingerprint.Length, settings, (nuint)encoded.Length, &buffer);
        Rejection? rejection = null;
        if (buffer.Bytes != null) {
            var reader = new WireReader(new ReadOnlySpan<byte>(buffer.Bytes, (int)buffer.Length).ToArray());
            rejection = ContractCodec.ReadRejection(reader);
            reader.EnsureEnd();
        }
        ((delegate* unmanaged[Cdecl]<CrestBuffer*, void>)&Exports.BufferFree)(&buffer);
        return (status, rejection);
    }

    public int Destroy() => ((delegate* unmanaged[Cdecl]<ulong, int>)&Exports.AppDestroy)(Handle);

    public void Dispose() => Destroy();

    #endregion

    #region Actions - Changes

    /// The changes the core started itself since the last drain.
    public IReadOnlyList<Change> Drain() {
        CrestBuffer buffer;
        Assert.Equal(CoreStatus.Ok, ((delegate* unmanaged[Cdecl]<ulong, CrestBuffer*, int>)&Exports.AppDrain)(Handle, &buffer));
        var reader = new WireReader(new ReadOnlySpan<byte>(buffer.Bytes, (int)buffer.Length).ToArray());
        ((delegate* unmanaged[Cdecl]<CrestBuffer*, void>)&Exports.BufferFree)(&buffer);
        var changes = reader.ReadList(() => ContractCodec.ReadChange(reader));
        reader.EnsureEnd();
        return changes;
    }

    public int SetWake(delegate* unmanaged[Cdecl]<nint, void> callback, nint context) =>
        ((delegate* unmanaged[Cdecl]<ulong, delegate* unmanaged[Cdecl]<nint, void>, nint, int>)&Exports.AppSetWake)(Handle, callback, context);

    #endregion

    #region Actions - Stored session

    /// Settles the stored session's sync stages; OK at once while the file
    /// holds no session.
    public int SettleSync() => ((delegate* unmanaged[Cdecl]<ulong, int>)&Exports.AppSettleSync)(Handle);

    #endregion

    #region Actions - Messages

    /// The changes an intent published; fails the test on any other answer.
    public IReadOnlyList<Change> Send(Intent intent) {
        var (status, bytes) = Dispatch(Encode(writer => ContractCodec.WriteIntent(writer, intent)));
        Assert.Equal(CoreStatus.Ok, status);
        var reader = new WireReader(bytes);
        var changes = reader.ReadList(() => ContractCodec.ReadChange(reader));
        reader.EnsureEnd();
        return changes;
    }

    /// The rule that refused an intent; fails the test on any other answer.
    public Rejection Refuse(Intent intent) {
        var (status, bytes) = Dispatch(Encode(writer => ContractCodec.WriteIntent(writer, intent)));
        Assert.Equal(CoreStatus.Rejected, status);
        var reader = new WireReader(bytes);
        var rejection = ContractCodec.ReadRejection(reader);
        reader.EnsureEnd();
        return rejection;
    }

    /// A query's answer, read with `read`; fails the test on any other answer.
    public TAnswer Ask<TAnswer>(Query<TAnswer> query, Func<WireReader, TAnswer> read) {
        var (status, bytes) = Ask(Encode(writer => ContractCodec.WriteQuery(writer, query)));
        Assert.Equal(CoreStatus.Ok, status);
        var reader = new WireReader(bytes);
        var answer = read(reader);
        reader.EnsureEnd();
        return answer;
    }

    /// The rule that refused a query; fails the test on any other answer.
    public Rejection Refuse<TAnswer>(Query<TAnswer> query) {
        var (status, bytes) = Ask(Encode(writer => ContractCodec.WriteQuery(writer, query)));
        Assert.Equal(CoreStatus.Rejected, status);
        var reader = new WireReader(bytes);
        var rejection = ContractCodec.ReadRejection(reader);
        reader.EnsureEnd();
        return rejection;
    }

    public (int Status, byte[] Bytes) Dispatch(ReadOnlySpan<byte> intent) =>
        Call((delegate* unmanaged[Cdecl]<ulong, byte*, nuint, CrestBuffer*, int>)&Exports.AppDispatch, intent);

    public (int Status, byte[] Bytes) Ask(ReadOnlySpan<byte> query) =>
        Call((delegate* unmanaged[Cdecl]<ulong, byte*, nuint, CrestBuffer*, int>)&Exports.AppQuery, query);

    public static byte[] Encode(Action<WireWriter> write) {
        var writer = new WireWriter();
        write(writer);
        return writer.WrittenSpan.ToArray();
    }

    private (int Status, byte[] Bytes) Call(delegate* unmanaged[Cdecl]<ulong, byte*, nuint, CrestBuffer*, int> entry,
        ReadOnlySpan<byte> message) {
        CrestBuffer buffer;
        int status;
        fixed (byte* input = message) status = entry(Handle, input, (nuint)message.Length, &buffer);
        var bytes = buffer.Bytes == null ? [] : new ReadOnlySpan<byte>(buffer.Bytes, (int)buffer.Length).ToArray();
        ((delegate* unmanaged[Cdecl]<CrestBuffer*, void>)&Exports.BufferFree)(&buffer);
        Assert.True(buffer.Bytes == null && buffer.Length == 0);
        return (status, bytes);
    }

    #endregion
}
