using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public const float RepairRadius = 92;
    public const float RepairDuration = 3.5f;
    public const float HarborRepairHull = 50;
    float repairRemaining;
    public bool RepairsUsed { get; private set; }
    public bool Repairing => repairRemaining > 0;
    public bool RepairsAvailable => !RepairsUsed && !BossSlain;
    public bool AtRepairBerth => Vector2.DistanceSquared(Position, StartingArea.RepairBerth) <= RepairRadius * RepairRadius;
    public bool CanTieUp => AtRepairBerth && RepairsAvailable && Health < MaxHealth && Velocity.LengthSquared() <= 60 * 60;
    public float RepairProgress => Repairing ? 1 - repairRemaining / RepairDuration : 0;

    public bool ToggleHarborRepairs()
    {
        if (!IsActive) return false;
        if (Repairing)
        {
            InterruptHarborRepairs();
            return true;
        }
        if (!CanTieUp || Health <= 0) return false;
        repairRemaining = RepairDuration;
        Events.Add(new("repairStart", StartingArea.RepairBerth, RepairRadius));
        return true;
    }

    void UpdateHarborRepairs(float dt, SailInput input)
    {
        if (!Repairing) return;
        if (!AtRepairBerth || input.Move != Vector2.Zero || input.Boost || input.Maneuver)
        {
            InterruptHarborRepairs();
            return;
        }
        if (Health >= MaxHealth)
        {
            repairRemaining = 0;
            return;
        }
        repairRemaining = Math.Max(0, repairRemaining - dt);
        if (Repairing) return;

        RepairsUsed = true;
        Heal(HarborRepairHull);
        Events.Add(new("repairDone", StartingArea.RepairBerth, RepairRadius));
    }

    void InterruptHarborRepairs()
    {
        if (!Repairing) return;
        repairRemaining = 0;
        Events.Add(new("repairInterrupted", StartingArea.RepairBerth));
    }
}
