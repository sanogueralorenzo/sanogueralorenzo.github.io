using System.Numerics;
namespace WizNDragons.Core;

public sealed partial class Flight
{
    public bool IsBoosting { get; private set; }
    public Vector2 CurrentFlow { get; private set; }
    public int BoostStarts { get; private set; }
    public int CrystalCollected { get; private set; }
    public int PotionsBroken { get; private set; }
    public float CurrentRideTime { get; private set; }

    bool UpdateMovement(float dt, FlightInput input)
    {
        var direction = SkyWorld.Unit(input.Move);
        if (!input.Boost) BoostExhausted = false;
        bool boosting = input.Boost && !BoostExhausted && (IsBoosting ? Boost > 0 : Boost >= 8) && direction != Vector2.Zero;
        if (direction != Vector2.Zero)
            Heading = ApproachAngle(Heading, MathF.Atan2(direction.Y, direction.X) + MathF.PI / 2, dt * (boosting ? 12 : 10));
        var forward = new Vector2(MathF.Sin(Heading), -MathF.Cos(Heading));
        if (boosting && !IsBoosting)
        {
            Boost = Math.Max(0, Boost - 8);
            Velocity = Vector2.Lerp(Velocity, forward * Speed * 2.05f, .65f);
            BoostStarts++; Events.Add(new("boostStart", Position));
        }
        Boost = Math.Clamp(Boost + dt * (boosting ? -38 : input.Boost && BoostExhausted ? 0 : 23), 0, 100);
        if (boosting && Boost <= 0) { BoostExhausted = true; boosting = false; }
        IsBoosting = boosting;
        CurrentFlow = World.FlowAt(Position);
        if (CurrentFlow.LengthSquared() > 100) CurrentRideTime += dt;
        // The broom responds first; a short velocity lag lets the behind drift through the turn.
        var wanted = (direction == Vector2.Zero ? Vector2.Zero : forward * Speed * (boosting ? 2.05f : 1)) + CurrentFlow;
        Velocity = Vector2.Lerp(Velocity, wanted, 1 - MathF.Exp(-dt * (direction == Vector2.Zero ? 4.5f : boosting ? 7 : 4)));
        var old = Position;
        Position += Velocity * dt;
        Distance += Vector2.Distance(old, Position); MaxDistance = Math.Max(MaxDistance, Position.Length());
        World.Stream(Position);
        foreach (var p in World.Places) if (Vector2.Distance(Position, p.Position) < 680) World.Discovered.Add(p.Id);
        return boosting;
    }
    void CollectEncounters()
    {
        foreach (var place in World.Places)
        {
            if (place.Kind is not (PlaceKind.Crystal or PlaceKind.Potion) || World.Depletion.ContainsKey(place.Id)) continue;
            bool potion = place.Kind == PlaceKind.Potion;
            if (Vector2.Distance(Position, place.Position) > place.Radius + 45) continue;
            if (potion && Health >= MaxHealth) continue;
            World.Depletion[place.Id] = 1;
            int reward = potion ? 25 : 12;
            if (potion) Heal(reward); else Xp += reward;
            if (potion) PotionsBroken++; else CrystalCollected++;
            Events.Add(new(potion ? "potion" : "crystal", place.Position, reward));
        }
    }
}
