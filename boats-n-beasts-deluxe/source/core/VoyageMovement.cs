using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public bool IsBoosting { get; private set; }
    public Vector2 CurrentFlow { get; private set; }
    public bool RidingCurrent { get; private set; }
    public int BoostStarts { get; private set; }
    public int TreasureCollected { get; private set; }
    public int BarrelsBroken { get; private set; }
    public float CurrentRideTime { get; private set; }

    void UpdateMovement(float dt, SailInput input)
    {
        var direction = OceanWorld.Unit(input.Move);
        float throttle = Math.Min(1, input.Move.Length());
        if (!input.Boost) BoostExhausted = false;
        bool boosting = input.Boost && !BoostExhausted && (IsBoosting ? Boost > 0 : Boost >= 8) && direction != Vector2.Zero;
        if (direction != Vector2.Zero)
            Heading = ApproachAngle(Heading, MathF.Atan2(direction.X, -direction.Y), 1 - MathF.Exp(-dt * (boosting ? 15 : 13)));
        var forward = Forward;
        CurrentFlow = World.FlowAt(Position);
        float flowSpeed = CurrentFlow.Length();
        RidingCurrent = flowSpeed >= 45 && throttle >= .45f &&
            Vector2.Dot(direction, CurrentFlow) >= flowSpeed * .8f &&
            Vector2.Dot(forward, CurrentFlow) >= flowSpeed * .8f;
        float currentRecovery = RidingCurrent ? 24 : 0;
        if (RidingCurrent) CurrentRideTime += dt;
        if (boosting && !IsBoosting)
        {
            Boost = Math.Max(0, Boost - 8);
            Velocity = Vector2.Lerp(Velocity, forward * Speed * 2.05f, .65f);
            BoostStarts++; Events.Add(new("boostStart", Position));
        }
        float boostChange = boosting ? -34 + currentRecovery
            : input.Boost && BoostExhausted ? 0 : BoostRecovery + currentRecovery;
        Boost = Math.Clamp(Boost + dt * boostChange, 0, 100);
        if (boosting && Boost <= 0) { BoostExhausted = true; boosting = false; }
        IsBoosting = boosting;
        // The bow responds first; a short velocity lag lets the stern drift through the turn.
        var wanted = forward * Speed * (boosting ? 2.05f : throttle) + CurrentFlow;
        Velocity = Vector2.Lerp(Velocity, wanted, 1 - MathF.Exp(-dt * (direction == Vector2.Zero ? 7 : boosting ? 10 : 7)));
        var old = Position;
        float hullRadius = Boat == BoatKind.Cutter ? 30 : 37;
        Position = World.Slide(old, Position + Velocity * dt, hullRadius);
        var bow = forward * 35;
        for (int pass = 0; pass < 2; pass++)
        {
            Position += World.Slide(old + bow, Position + bow, hullRadius) - (Position + bow);
            Position += World.Slide(old - bow, Position - bow, hullRadius) - (Position - bow);
        }
        Distance += Vector2.Distance(old, Position); MaxDistance = Math.Max(MaxDistance, Position.Length());
        World.Stream(Position);
        World.Observe(Position);
    }
    void CollectEncounters()
    {
        foreach (var place in World.Places)
        {
            if (place.Kind is not (PlaceKind.Treasure or PlaceKind.Barrel) || World.Depletion.ContainsKey(place.Id)) continue;
            bool barrel = place.Kind == PlaceKind.Barrel;
            if (barrel)
            {
                var forward = Forward;
                var alongHull = Position + forward * Math.Clamp(Vector2.Dot(place.Position - Position, forward), -35, 35);
                if (Vector2.Distance(alongHull, place.Position) > place.Radius + (Boat == BoatKind.Cutter ? 30 : 37)) continue;
            }
            else if (Vector2.Distance(Position, place.Position) > 140) continue;
            if (barrel && Health >= MaxHealth) continue;
            World.Depletion[place.Id] = 1;
            int reward = barrel ? 25 : Charter == Charter.Salvager ? 24 : 12;
            if (barrel) Heal(reward);
            else { Xp += reward; if (Charter == Charter.Salvager) silver += 2; }
            if (barrel) BarrelsBroken++; else TreasureCollected++;
            Events.Add(new(barrel ? "barrel" : "treasure", place.Position, reward));
        }
    }
}
