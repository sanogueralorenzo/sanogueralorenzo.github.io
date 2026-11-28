using System.Text.Json;
using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal static class HarborSave
{
    static readonly JsonSerializerOptions Options = new() { IgnoreReadOnlyProperties = true };
    static string Path => ProjectSettings.GlobalizePath("user://quay-log.json");

    public static HarborLedger Open()
    {
        if (!File.Exists(Path)) return new();
        var ledger = JsonSerializer.Deserialize<HarborLedger>(File.ReadAllText(Path))
            ?? throw new InvalidDataException("The harbor log is empty.");
        if (ledger.AtSea == 0) return ledger;
        ledger = ledger.Land(Passage.LanternSound, false, ledger.AtSea);
        Write(ledger);
        return ledger;
    }

    public static void Write(HarborLedger ledger)
    {
        File.WriteAllText(Path + ".new", JsonSerializer.Serialize(ledger, Options));
        File.Move(Path + ".new", Path, true);
    }
}
