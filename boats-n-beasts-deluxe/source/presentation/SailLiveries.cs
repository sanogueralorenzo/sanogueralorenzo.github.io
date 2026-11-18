using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

public enum SailLivery { Original, WreckDiver, Beaconkeeper, StormLaurel }

sealed record SailDesign(SailLivery Livery, string Name, string Requirement, Color Cloth, Color Trim, Color Ink,
    Func<Voyage, DailyChallenge?, bool> Earned)
{
    public int Flag => 1 << (int)Livery;
    public static SailDesign For(SailLivery livery) => All[(int)livery];
    public static readonly SailDesign[] All =
    [
        new(SailLivery.Original, "Original colors", "The boat’s original sail.", Colors.White, Colors.White, Colors.White,
            (_, _) => false),
        new(SailLivery.WreckDiver, "Wreck Diver", "Tow wreck salvage to a beacon.", new("f6d396"), new("a74732"), new("733028"),
            (run, _) => run.Salvage.Delivered),
        new(SailLivery.Beaconkeeper, "Beaconkeeper", "Light all three beacons and defeat Crownclaw.", new("bcece0"), new("2d6a73"), new("164755"),
            (run, _) => run.BossSlain && run.BeaconsLit == run.Beacons.Count),
        new(SailLivery.StormLaurel, "Storm Laurel", "Clear a daily challenge.", new("e8dbee"), new("554683"), new("533565"),
            (run, daily) => daily is { } challenge && challenge.Qualifies(run))
    ];

    public Color Panel(int column, int row) => Livery switch
    {
        SailLivery.WreckDiver => column is 0 or 7 || row <= 1 || (row <= 3 && (column == row - 1 || column == 8 - row))
            ? Trim : Cloth,
        SailLivery.Beaconkeeper => column is 0 or 7 || row == 7 ? Trim : row == 6 ? new("8acbc2") : Cloth,
        _ => column is 0 or 7 || row is 0 or 7 ? Trim : row == 1 || row == 6 ? new("b69dcd") : Cloth
    };
}
