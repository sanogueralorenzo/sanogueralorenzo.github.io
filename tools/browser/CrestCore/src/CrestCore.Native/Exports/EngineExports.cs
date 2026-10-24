using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

/// An engine binding's function table, `crest_engine_binding_t`. The core
/// copies it at registration; `Context` is the binding's own and is handed back
/// with every call.
[StructLayout(LayoutKind.Sequential)]
public unsafe struct CrestEngineBinding {
    public nint Context;
    /// Called once when registration succeeds, with the app, the engine's
    /// handle, the function to report through and the function to ask
    /// through; may be null.
    public delegate* unmanaged[Cdecl]<nint, ulong, ulong, delegate* unmanaged[Cdecl]<ulong, ulong, byte*, nuint, int>,
        delegate* unmanaged[Cdecl]<ulong, ulong, byte*, nuint, delegate* unmanaged[Cdecl]<nint, byte*, nuint, void>, nint, int>,
        void> Attach;
    /// Runs one encoded command; the bytes are borrowed for the call.
    public delegate* unmanaged[Cdecl]<nint, byte*, nuint, void> Run;
}

public static unsafe partial class Exports {
    #region Variables

    /// Each registered engine, by handle, with the app it registered with.
    private static readonly ConcurrentDictionary<ulong, (CrestApp App, ulong AppHandle, Engine Engine)> Engines = new();

    #endregion

    #region Actions - Native exports

    [UnmanagedCallersOnly(EntryPoint = "crest_engine_register", CallConvs = [typeof(CallConvCdecl)])]
    public static int EngineRegister(ulong app, byte* fingerprint, nuint length, byte* registration, nuint registrationLength,
        CrestEngineBinding* binding, ulong* engine, CrestBuffer* rejection) {
        if (engine == null || rejection == null) return CoreStatus.InvalidArgument;
        *engine = 0;
        *rejection = default;
        if (binding == null || binding->Run == null || fingerprint == null && length != 0
            || registration == null && registrationLength != 0) return CoreStatus.InvalidArgument;
        if (registrationLength > MessageLimitAttribute.DefaultBytes) return CoreStatus.LimitExceeded;
        try {
            if (!Apps.TryGetValue(app, out var crest)) return CoreStatus.InvalidHandle;
            if (length != (nuint)ContractCodec.EngineFingerprint.Length
                || !new ReadOnlySpan<byte>(fingerprint, (int)length).SequenceEqual(ContractCodec.EngineFingerprint))
                return CoreStatus.VersionMismatch;
            var reader = new WireReader(new ReadOnlySpan<byte>(registration, (int)registrationLength).ToArray());
            var settings = Finished(ContractCodec.ReadEngineRegistration(reader), reader);
            var table = *binding;
            Engine registered;
            try {
                registered = crest.RegisterEngine(settings, command => Run(table, command));
            } catch (Rejected refused) {
                var writer = new WireWriter();
                ContractCodec.WriteRejection(writer, refused.Rejection);
                *rejection = Allocate(writer.WrittenSpan);
                return CoreStatus.Rejected;
            }
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Engines.TryAdd(id, (crest, app, registered))) {
                crest.UnregisterEngine(registered);
                return CoreStatus.InternalError;
            }
            *engine = id;
            if (table.Attach != null) table.Attach(table.Context, app, id, &EngineReport, &EngineAsk);
            return CoreStatus.Ok;
        } catch (WireFormatException) {
            return CoreStatus.InvalidMessage;
        } catch {
            return CoreStatus.InternalError;
        }
    }

    /// Reports what an engine saw happen to one of its pages. Never refused:
    /// OK for a report about a page the core no longer knows. A binding's
    /// `attach` receives this function too.
    [UnmanagedCallersOnly(EntryPoint = "crest_engine_report", CallConvs = [typeof(CallConvCdecl)])]
    public static int EngineReport(ulong app, ulong engine, byte* report, nuint length) {
        if (report == null && length != 0) return CoreStatus.InvalidArgument;
        int tag = WireReader.PeekTag(new ReadOnlySpan<byte>(report, (int)Math.Min(length, (nuint)WireReader.MaximumTagBytes)));
        if (length > (nuint)ContractCodec.MaximumEngineEventBytes(tag)) return CoreStatus.LimitExceeded;
        try {
            if (!Engines.TryGetValue(engine, out var entry) || entry.AppHandle != app) return CoreStatus.InvalidHandle;
            var reader = new WireReader(new ReadOnlySpan<byte>(report, (int)length).ToArray());
            entry.App.Report(entry.Engine, Finished(ContractCodec.ReadEngineEvent(reader), reader));
            return CoreStatus.Ok;
        } catch (Rejected) {
            // A report is never refused: one the core's rules turn away
            // changes nothing, like a report about a page the core forgot.
            return CoreStatus.Ok;
        } catch (WireFormatException) {
            return CoreStatus.InvalidMessage;
        } catch {
            return CoreStatus.InternalError;
        }
    }

    /// Answers what an engine asks about one of its pages while it waits:
    /// `answer` receives the encoded answer, borrowed for the call, with
    /// `context`, before this returns OK. A binding's `attach` receives this
    /// function too.
    [UnmanagedCallersOnly(EntryPoint = "crest_engine_ask", CallConvs = [typeof(CallConvCdecl)])]
    public static int EngineAsk(ulong app, ulong engine, byte* question, nuint length,
        delegate* unmanaged[Cdecl]<nint, byte*, nuint, void> answer, nint context) {
        if (question == null && length != 0 || answer == null) return CoreStatus.InvalidArgument;
        int tag = WireReader.PeekTag(new ReadOnlySpan<byte>(question, (int)Math.Min(length, (nuint)WireReader.MaximumTagBytes)));
        if (length > (nuint)ContractCodec.MaximumEngineQuestionBytes(tag)) return CoreStatus.LimitExceeded;
        try {
            if (!Engines.TryGetValue(engine, out var entry) || entry.AppHandle != app) return CoreStatus.InvalidHandle;
            var reader = new WireReader(new ReadOnlySpan<byte>(question, (int)length).ToArray());
            var asked = Finished(ContractCodec.ReadEngineQuestion(reader), reader);
            var writer = new WireWriter();
            ContractCodec.WriteEngineAnswer(writer, entry.App, entry.Engine, asked);
            fixed (byte* bytes = writer.WrittenSpan) answer(context, bytes, (nuint)writer.WrittenSpan.Length);
            return CoreStatus.Ok;
        } catch (WireFormatException) {
            return CoreStatus.InvalidMessage;
        } catch {
            return CoreStatus.InternalError;
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_engine_unregister", CallConvs = [typeof(CallConvCdecl)])]
    public static int EngineUnregister(ulong app, ulong engine) {
        try {
            if (!Engines.TryGetValue(engine, out var entry) || entry.AppHandle != app || !Engines.TryRemove(engine, out _))
                return CoreStatus.InvalidHandle;
            entry.App.UnregisterEngine(entry.Engine);
            return CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    #endregion

    #region Actions - Engines

    /// Encodes one command and hands it to the binding's `run`.
    private static void Run(CrestEngineBinding binding, EngineCommand command) {
        var writer = new WireWriter();
        ContractCodec.WriteEngineCommand(writer, command);
        fixed (byte* bytes = writer.WrittenSpan) binding.Run(binding.Context, bytes, (nuint)writer.WrittenSpan.Length);
    }

    /// Forgets the engines an app registered, which is going away.
    private static void ForgetEngines(ulong app) {
        foreach (var entry in Engines.Where(entry => entry.Value.AppHandle == app)) Engines.TryRemove(entry.Key, out _);
    }

    #endregion
}
