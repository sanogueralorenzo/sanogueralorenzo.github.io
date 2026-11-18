namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public bool IsSwapOffer(int option) => (uint)option < Weapons.Length && WeaponCount == WeaponSlots &&
        Weapons[option] == 0 && UpgradeChoices.Contains(option);

    public bool CanSwapWeapon(int incoming, int outgoing) => Mode == VoyageMode.Upgrade && PendingUpgrades > 0 &&
        IsSwapOffer(incoming) && (uint)outgoing < Weapons.Length && Weapons[outgoing] > 0 && outgoing != (int)BoatRig.Starter(Boat);

    public bool SwapWeapon(int incoming, int outgoing)
    {
        if (!CanSwapWeapon(incoming, outgoing)) return false;
        var previous = ActiveCombo;
        Weapons[incoming] = Weapons[outgoing];
        Weapons[outgoing] = 0;
        var current = ActiveCombo;
        Cooldowns[outgoing] = Cooldowns[incoming] = 0;
        var removed = (WeaponKind)outgoing;
        Shots.RemoveAll(shot => !shot.Hostile && shot.Kind == removed);
        if (removed == WeaponKind.Cannon) CannonAim = default;
        if (removed == WeaponKind.Harpoon) HarpoonAim = default;
        foreach (var enemy in Enemies)
        {
            if (removed == WeaponKind.Harpoon) enemy.Pull = 0;
            if (removed is WeaponKind.Harpoon or WeaponKind.Mine) enemy.PullMine = null;
            if (previous == WeaponCombo.Riptide && current != previous) enemy.Drenched = 0;
        }

        Events.Add(new("weaponSwapped", Position, incoming));
        if (current != null && current != previous) Events.Add(new("comboFitted", Position, incoming));
        FinishUpgrade();
        return true;
    }

    bool CompletesWeaponPair(int option) =>
        WeaponCombo.ForUpgrade(option) is { } combo && Rank(combo.Partner(option)) > 0;

    void AddSwapOffer()
    {
        var candidates = Enumerable.Range(0, Weapons.Length).Where(i => Weapons[i] == 0).ToArray();
        var pairs = candidates.Where(CompletesWeaponPair).ToArray();
        if (pairs.Length > 0) candidates = pairs;
        if (candidates.Length > 0) UpgradeChoices.Add(candidates[buildRandom.Index(candidates.Length)]);
    }
}
