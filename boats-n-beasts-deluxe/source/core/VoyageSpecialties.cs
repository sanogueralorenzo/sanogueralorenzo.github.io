namespace BoatsNBeasts.Core;

public enum Specialty { None, Windrunner, Shipwright, Gunner }

public sealed partial class Voyage
{
    public const int SpecialtyLevel = 5;
    public const int FirstSpecialtyOption = 10;
    public Specialty Specialty { get; private set; }
    public float ChainDuration => Specialty == Specialty.Shipwright ? 7 : 5;
    public float BoostRecovery => Specialty == Specialty.Windrunner ? 45 : 30;

    bool IsSpecialtyLevel => Level - PendingUpgrades + 1 == SpecialtyLevel;

    void SelectSpecialty(int option)
    {
        Specialty = (Specialty)(option - FirstSpecialtyOption + 1);
        if (Specialty == Specialty.Windrunner) Boost = 100;
        if (Specialty == Specialty.Gunner) ManeuverCooldown = 0;
    }
}
