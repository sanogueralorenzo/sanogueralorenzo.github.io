using System.Text.Json;
using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal sealed class HarborSave : IDisposable
{
    static readonly JsonSerializerOptions Options = new() { IgnoreReadOnlyProperties = true };
    static string Path => ProjectSettings.GlobalizePath("user://quay-log.json");

    FileStream? writer;

    public HarborLedger Open()
    {
        try { writer = new FileStream(Path + ".lock", FileMode.OpenOrCreate, System.IO.FileAccess.ReadWrite, FileShare.None); }
        catch (IOException error) { throw new IOException("Close any other game using this harbor log and try again.", error); }
        if (!File.Exists(Path)) return new();
        var ledger = JsonSerializer.Deserialize<HarborLedger>(File.ReadAllText(Path))
            ?? throw new InvalidDataException("The harbor log is empty.");
        if (ledger.AtSea == 0) return ledger;
        ledger = ledger.Land(Passage.LanternSound, false, ledger.AtSea);
        Write(ledger);
        return ledger;
    }

    public void Dispose() => writer?.Dispose();

    public void Write(HarborLedger ledger)
    {
        File.WriteAllText(Path + ".new", JsonSerializer.Serialize(ledger, Options));
        File.Move(Path + ".new", Path, true);
    }
}
