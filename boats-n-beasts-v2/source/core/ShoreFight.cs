using System.Numerics;

namespace BoatsNBeasts.Core;

public enum QuayPhase { Landing, Fork, Watch, Belfry, ChainWatch, Fishery, Foundry, Ascent, Warden, Rescue, Homeward, Lost }
public enum BellStroke { Sweep, Toll, Fall }

public sealed class ShoreFoe(Vector2 position, bool warden, bool mortar = false)
{
    public Vector2 Position = position, Aim = Vector2.UnitY, Target;
    public readonly bool Warden = warden, Mortar = mortar;
    public readonly int MaxHealth = warden ? 112 : mortar ? 24 : 30;
    public int Health = warden ? 112 : mortar ? 24 : 30;
    public float Rest = 1, Warning, Winding, Stagger, Flash, Strike;
    public int Pattern;
    public BellStroke Stroke;
    public float Reach => Warden ? 2.6f : 1.25f;
    public float SweepCos => Warden ? .14f : .25f;

    public bool Threatens(Vector2 point)
    {
        if (Stroke == BellStroke.Fall) return Vector2.Distance(Target, point) <= 1.32f;
        var offset = point - Position;
        float distance = offset.Length();
        if (Stroke == BellStroke.Toll) return distance >= 1.48f && distance <= 3.5f;
        return distance <= Reach && (distance < .1f || Vector2.Dot(offset / distance, Aim) >= SweepCos);
    }
}

public sealed class ShoreFight
{
    public static readonly Vector2 Dock = QuayPaths.Dock;
    public static readonly Vector2[] Bells = QuayPaths.Bells;
    public static readonly string[] StationNames = ["Fishers’ Watch", "Founders’ Watch"];
    public static readonly string[] Fittings = ["Quickline", "Sawtooth edge"];
    public int FirstBell { get; private set; } = -1;
    public bool StormBroken { get; private set; }
    public bool[] Chains { get; } = [false, false];
    public bool Bound => StormBroken && Chains.Any(link => link);
    public readonly bool[] Floats = new bool[2];
    public Vector2 Billet { get; private set; }
    public static readonly Vector2 Mould = Bells[1] + new Vector2(1.1f, .72f);
    Vector2 billetVelocity;
    public Vector2 FloatAt(int id)
    {
        var offset = id == 0 ? new Vector2(-2.86f, -.61f + MathF.Sin(Clock * .85f) * .75f)
            : new Vector2(MathF.Sin(Clock * .72f) * .85f + .78f, 2.87f);
        return Bells[0] + offset;
    }
    public bool AtBelfry => Vector2.Distance(Player, QuayPaths.Belfry) < 1.45f;
    public readonly bool[] Rung = new bool[2];
    public readonly List<ShoreFoe> Foes = [];
    public readonly List<Vector2> Coins = [];
    public QuayPhase Phase { get; private set; }
    public Vector2 Player = Dock, Crew = Dock + new Vector2(.5f, -.3f), Facing = -Vector2.UnitY, HookEnd;
    public int Health = 6, Silver;
    public float Dash, Hook, Swung, Hurt, HookWait, DodgeWait, Clock;
    public string Voice = "Handbells on legs! Press J to cut. K hooks one when the red mark appears.";
    public bool Boarded { get; private set; }
    public Vector2 Keeper { get; private set; }
    public bool BesideKeeper => Vector2.Distance(Player, Keeper) < 1.35f;
    readonly Queue<Vector2> returnTrail = new();
    Vector2 lastStep;
    public string Objective => Phase switch
    {
        QuayPhase.Landing => "Break through the landing watch",
        QuayPhase.Fork => "Choose a signal station",
        QuayPhase.Watch => "Hold the signal station",
        QuayPhase.Belfry => "Ring the other shore bell",
        QuayPhase.ChainWatch => "Free the crew at the second station",
        QuayPhase.Fishery => $"Hook the drift nets  ·  {Floats.Count(x => x)}/2",
        QuayPhase.Foundry => "Drive the bronze pin into the mould",
        QuayPhase.Ascent => "Fit the tongue at the upper belfry",
        QuayPhase.Warden => Bound ? "Cut both lines mooring the keeper" : "Free the keeper from the bell",
        QuayPhase.Rescue => "Help the keeper out of the bronze",
        QuayPhase.Homeward => "Lead the keeper back to the skiff",
        _ => "The crew pulls you out"
    };
    readonly Random random;
    public int MaxHealth { get; }
    float swingWait, invulnerability;
    Vector2 dashDirection;

    public ShoreFight(int seed, int stores)
    {
        random = new(seed);
        MaxHealth = Health = 6 + Math.Clamp(stores, 0, 2);
        Foes.Add(new(new(-1.55f, .15f), false));
        Foes.Add(new(new(1.5f, -1.0f), false, true) { Rest = 2.3f });
    }
    public int NearBell => Array.FindIndex(Bells, p => Vector2.Distance(Player, p) < 1.25f);
    public bool AtDock => Vector2.Distance(Player, Dock) < 1.1f;
    public void Interact()
    {
        if (Phase == QuayPhase.Homeward && AtDock && Vector2.Distance(Keeper, Dock) < 2.7f) { Boarded = true; return; }
        if (Phase == QuayPhase.Rescue && BesideKeeper)
        {
            Phase = QuayPhase.Homeward; lastStep = Player; returnTrail.Enqueue(Player);
            Voice = "Carry her book. She wrote down every boat they turned away.";
            return;
        }
        if (Phase == QuayPhase.Foundry && Vector2.Distance(Player, Bells[1]) < 1.25f)
        {
            Billet = Bells[1] + new Vector2(-.80f, -.32f); billetVelocity = Vector2.Zero;
            Voice = "J knocks the pin away from you. K draws it back."; return;
        }
        if (Phase == QuayPhase.Ascent && AtBelfry)
        {
            Phase = QuayPhase.Warden; Health = Math.Min(MaxHealth, Health + 2);
            Voice = "The old tongue fits. Hear a voice? Hook the hammer when it rises!";
            Foes.Add(new(QuayPaths.Summit + new Vector2(0, -.55f), true) { Rest = 1.4f });
            return;
        }
        int bell = NearBell;
        if (Phase is not (QuayPhase.Fork or QuayPhase.Belfry) || bell < 0 || Rung[bell]) return;
        Rung[bell] = true;
        if (Phase == QuayPhase.Fork)
        {
            FirstBell = bell; Phase = QuayPhase.Watch;
            Voice = bell == 0 ? "A quickline reel! I can hook twice as often with this." : "Sawtooth edge from the foundry. It'll bite straight through bronze.";
        }
        else
        {
            Phase = QuayPhase.ChainWatch;
            Voice = "The line is singing! Here comes the last toll crew.";
        }
        float side = bell == 0 ? 1 : -1;
        var station = Bells[bell];
        bool mortar = random.Next(2) == 0;
        Foes.Add(new(station + new Vector2(side * 1.45f, -1.1f), false, mortar) { Rest = 1.65f });
        Foes.Add(new(station + new Vector2(side * 1.70f, 1.13f), false, !mortar) { Rest = 1.2f });
        if (Phase == QuayPhase.ChainWatch) Foes.Add(new(station + new Vector2(-side * 1.66f, .4f), false) { Rest = 2.7f });
    }
    public void Tick(float dt, Vector2 move, bool cut, bool dodge, bool hook)
    {
        if (Phase == QuayPhase.Lost || Boarded) return;
        Clock += dt;
        Hurt = Decay(Hurt, dt); Swung = Decay(Swung, dt); Hook = Decay(Hook, dt);
        swingWait = Decay(swingWait, dt); invulnerability = Decay(invulnerability, dt);
        HookWait = Decay(HookWait, dt); DodgeWait = Decay(DodgeWait, dt); Dash = Decay(Dash, dt);
        if (move.LengthSquared() > 1) move = Vector2.Normalize(move);
        if (move.LengthSquared() > .01f) Facing = Vector2.Normalize(move);
        if (dodge && DodgeWait == 0) { Dash = .23f; DodgeWait = 1.15f; dashDirection = Facing; invulnerability = .31f; }
        Player = QuayPaths.Walkable(Player + (Dash > 0 ? dashDirection * 8.0f : move * 2.55f) * dt);
        Crew = QuayPaths.Walkable(Crew + (Player - Facing * .65f + new Vector2(.25f, -.25f) - Crew) * Math.Min(1, dt * 4.3f));
        if (Phase == QuayPhase.Homeward)
        {
            if (Vector2.Distance(lastStep, Player) > .18f) { lastStep = Player; returnTrail.Enqueue(Player); }
            if (Vector2.Distance(Keeper, Player) > .88f && returnTrail.TryPeek(out var next))
            {
                var step = next - Keeper;
                if (step.Length() < .075f) returnTrail.Dequeue();
                else Keeper += Direction(step) * Math.Min(step.Length(), dt * 3.2f);
            }
        }
        if (Phase == QuayPhase.Fishery && hook && HookWait == 0)
        {
            for (int i = 0; i < Floats.Length; i++)
                if (!Floats[i] && Vector2.Distance(Player, FloatAt(i)) < 2.45f)
                {
                    Floats[i] = true; Hook = .55f; HookWait = 1.1f; HookEnd = FloatAt(i); Silver++;
                    Voice = "I have the corks. There's another net around the rim.";
                    if (Floats.All(x => x)) FinishStation();
                    break;
                }
        }
        if (Phase == QuayPhase.Foundry)
        {
            if (hook && HookWait == 0 && Vector2.Distance(Player, Billet) < 3.4f)
            {
                Hook = .43f; HookWait = 1.1f; HookEnd = Billet; billetVelocity = Direction(Player - Billet) * 3.6f;
            }
            if (cut && swingWait == 0 && Vector2.Distance(Player, Billet) < 1.28f)
                billetVelocity = Direction(Billet - Player) * 5.0f;
            Billet += billetVelocity * dt;
            billetVelocity *= MathF.Exp(-5f * dt);
            var offset = (Billet - Bells[1]) / new Vector2(1.65f, 1.40f);
            if (offset.LengthSquared() > 1) Billet = Bells[1] + Vector2.Normalize(offset) * new Vector2(1.65f, 1.40f);
            if (Vector2.Distance(Billet, Mould) < .48f) { Silver += 2; FinishStation(); }
        }
        var nearest = Foes.MinBy(f => Vector2.DistanceSquared(f.Position, Player));
        if (cut && swingWait == 0 && Dash == 0)
        {
            Swung = .24f; swingWait = .40f;
            if (nearest != null && Vector2.Distance(Player, nearest.Position) < 1.75f)
                Facing = Direction(nearest.Position - Player);
            if (Bound)
                for (int i = 0; i < Chains.Length; i++)
                    if (Chains[i] && Vector2.Distance(Player, QuayPaths.Anchors[i]) < 1.25f)
                    { Chains[i] = false; Voice = Bound ? "One free. Get the other line!" : "The cables are down. Bring that bell apart!"; }
            foreach (var foe in Foes)
            {
                var toFoe = foe.Position - Player;
                if (toFoe.Length() <= (foe.Warden ? 1.62f : 1.24f) && Vector2.Dot(Facing, Direction(toFoe)) > -.12f)
                {
                    if (foe.Warden && Bound) continue;
                    int damage = foe.Stagger > 0 ? 10 : foe.Warden && foe.Rest <= 0 ? 3 : 6;
                    foe.Health -= damage + (FirstBell == 1 ? 2 : 0); foe.Flash = .17f;
                }
            }
        }
        if (hook && HookWait == 0 && nearest != null && Vector2.Distance(Crew, nearest.Position) <= 3.8f)
        {
            bool interrupt = nearest.Warning > 0;
            Hook = .44f; HookWait = FirstBell == 0 ? 3.0f : 5.5f; HookEnd = nearest.Position;
            if (!nearest.Warden || !Bound) nearest.Health -= interrupt ? 10 : 3; nearest.Stagger = interrupt ? 1.35f : .5f;
            nearest.Warning = 0; nearest.Rest = .7f; nearest.Flash = .2f;
            Voice = interrupt ? "Got the clapper! Hit the crack!" : "Line's fast. Get close!";
        }
        for (int i = Foes.Count - 1; i >= 0; i--)
        {
            var foe = Foes[i];
            if (foe.Health <= 0)
            {
                int count = foe.Warden ? 6 : 2;
                for (int n = 0; n < count; n++)
                {
                    float angle = MathF.Tau * n / count;
                    Coins.Add(QuayPaths.Walkable(foe.Position + new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * .38f));
                }
                Foes.RemoveAt(i);
                if (foe.Warden) { Phase = QuayPhase.Rescue; Keeper = foe.Position; Voice = "The woman in the bell has a book tied to her wrist. Help her up."; }
                else if (Foes.Count == 0)
                {
                    switch (Phase)
                    {
                        case QuayPhase.Landing:
                            Phase = QuayPhase.Fork; Voice = "Fishers keep quickline at the west bell. Founders hone blades at the east. Pick one."; break;
                        case QuayPhase.Watch:
                        case QuayPhase.ChainWatch:
                            int active = Phase == QuayPhase.Watch ? FirstBell : 1 - FirstBell;
                            if (active == 0)
                            {
                                Phase = QuayPhase.Fishery; Voice = "Their warning nets are adrift. Walk to the bright corks and hook both lines with K.";
                            }
                            else
                            {
                                Phase = QuayPhase.Foundry; Billet = Bells[1] + new Vector2(-.8f, -.32f);
                                Voice = "The gate needs a bronze pin. Stand behind the blank and knock it into the striped mould with J.";
                            }
                            break;
                    }
                }
                continue;
            }
            if (foe.Warden && !StormBroken && foe.Health <= foe.MaxHealth * .58f)
            {
                StormBroken = true; Chains[0] = Chains[1] = true;
                foe.Position = QuayPaths.Summit;
                foe.Warning = foe.Stagger = 0; foe.Rest = 1;
                Voice = "He’s lashed to two winding posts. Cut both glowing ropes with J!";
            }
            EnemyTurn(foe, dt);
            var separation = Player - foe.Position;
            float clearance = foe.Warden ? .98f : .48f;
            if (separation.LengthSquared() < clearance * clearance)
                Player = QuayPaths.Walkable(foe.Position + Direction(separation) * clearance);
        }
        for (int i = Coins.Count - 1; i >= 0; i--)
            if (Vector2.Distance(Player, Coins[i]) < .90f) { Coins.RemoveAt(i); Silver++; }
        if (Health <= 0) { Phase = QuayPhase.Lost; Voice = "Hold my wrist. The boat's right here."; }
    }
    void FinishStation()
    {
        Health = Math.Min(MaxHealth, Health + 1);
        if (Rung.All(x => x))
        {
            Phase = QuayPhase.Ascent; Voice = "The nets are fast and the pin is seated. Take either high walk to the belfry.";
        }
        else
        {
            Phase = QuayPhase.Belfry; Voice = "The station hands share their rations. Cross to the other bell.";
        }
    }
    void EnemyTurn(ShoreFoe foe, float dt)
    {
        foe.Flash = Decay(foe.Flash, dt); foe.Strike = Decay(foe.Strike, dt);
        if (foe.Stagger > 0) { foe.Stagger = Decay(foe.Stagger, dt); return; }
        if (foe.Warning > 0)
        {
            foe.Warning = Decay(foe.Warning, dt);
            if (foe.Warning == 0)
            {
                foe.Strike = .28f;
                if (foe.Threatens(Player) && invulnerability == 0)
                { Health -= foe.Warden ? 2 : 1; Hurt = .26f; invulnerability = .92f; }
                foe.Rest = foe.Warden ? StormBroken ? .72f : 1.15f : 1.4f;
            }
            return;
        }
        var offset = Player - foe.Position;
        if (foe.Rest > 0) { foe.Rest = Decay(foe.Rest, dt); return; }
        foe.Aim = Direction(offset);
        BellStroke next = foe.Mortar || foe.Warden && Bound ? BellStroke.Fall :
            !foe.Warden ? BellStroke.Sweep :
            ((foe.Pattern + (StormBroken ? 1 : 0)) % 3) switch { 1 => BellStroke.Toll, 2 => BellStroke.Fall, _ => BellStroke.Sweep };
        if (!Bound && offset.Length() > (next == BellStroke.Fall ? 5.1f : foe.Reach * .85f))
        {
            foe.Position = QuayPaths.Walkable(foe.Position + foe.Aim * dt * (foe.Warden ? 1.35f : 1.7f));
            return;
        }
        foe.Stroke = next;
        foe.Pattern++; foe.Target = Player;
        foe.Winding = foe.Warden ? (foe.Health < foe.MaxHealth / 2 ? .72f : .94f) : .72f;
        foe.Warning = foe.Winding;
    }
    static Vector2 Direction(Vector2 offset) => offset.LengthSquared() > .0001f ? Vector2.Normalize(offset) : Vector2.UnitY;
    static float Decay(float value, float dt) => Math.Max(0, value - dt);
}
