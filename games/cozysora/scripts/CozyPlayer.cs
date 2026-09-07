using Godot;
using System.Globalization;

namespace CozySora;

/// <summary>Shared locomotion, input and following camera for both procedural characters.</summary>
public partial class CozyPlayer : CharacterBody3D
{
    [Signal] public delegate void ModeChangedEventHandler(string mode);
    [Signal] public delegate void MenuChangedEventHandler(bool open);
    public CozyMap World { get; private set; } = null!;
    public Camera3D Camera { get; private set; } = null!;
    public string Mode { get; private set; } = "cat";
    public bool MenuOpen { get; private set; } = true;
    public bool ShotMode { get; set; }
    public bool FixedView { get; private set; }
    public bool Grounded { get; private set; } = true;
    public bool Perched { get; private set; }
    public bool MouseCaptureEnabled { get; set; } = !OS.HasFeature("mobile");
    public Vector2 TouchMove { get; set; }
    private float _camYaw = -.08f, _camPitch = .09f, _heading = -.08f, _moveDirection = -.08f;
    private float _speed, _birdPitch, _bank, _cameraDistance = 4.2f;
    private double _elapsed, _gaitPhase, _stepPhase, _flapPhase;
    private float _flap, _animatedFlap, _animatedPerch = 1;
    private Vector3 _cameraLook, _lastCatPosition = new(-6.4f, 0, .2f), _registeredSpawn;
    private Aabb _flightBounds = new(new(-135, -30, -95), new(270, 140, 213));
    private readonly Dictionary<string, ulong> _tapUntil = new();
    private readonly Dictionary<string, bool> _touchActions = new();

    public static void ConfigureInput()
    {
        Dictionary<string, Key[]> keys = new()
        {
            ["move_left"] = [Key.A, Key.Left],
            ["move_right"] = [Key.D, Key.Right],
            ["move_forward"] = [Key.W, Key.Up],
            ["move_back"] = [Key.S, Key.Down],
            ["jump"] = [Key.Space],
            ["descend"] = [Key.C, Key.Ctrl],
            ["sprint"] = [Key.Shift],
            ["switch"] = [Key.Tab],
            ["pause"] = [Key.Escape],
            ["cry"] = [],
            ["look_left"] = [],
            ["look_right"] = [],
            ["look_up"] = [],
            ["look_down"] = []
        };
        Dictionary<string, JoyButton> buttons = new()
        {
            ["jump"] = JoyButton.A,
            ["descend"] = JoyButton.B,
            ["sprint"] = JoyButton.LeftShoulder,
            ["switch"] = JoyButton.Y,
            ["pause"] = JoyButton.Start,
            ["cry"] = JoyButton.X
        };
        Dictionary<string, (JoyAxis Axis, float Value)> axes = new()
        {
            ["move_left"] = (JoyAxis.LeftX, -1),
            ["move_right"] = (JoyAxis.LeftX, 1),
            ["move_forward"] = (JoyAxis.LeftY, -1),
            ["move_back"] = (JoyAxis.LeftY, 1),
            ["look_left"] = (JoyAxis.RightX, -1),
            ["look_right"] = (JoyAxis.RightX, 1),
            ["look_up"] = (JoyAxis.RightY, -1),
            ["look_down"] = (JoyAxis.RightY, 1)
        };
        foreach (var (suffix, codes) in keys)
        {
            string action = "cozy_" + suffix;
            if (InputMap.HasAction(action)) continue;
            InputMap.AddAction(action, .2f);
            foreach (var code in codes) InputMap.ActionAddEvent(action, new InputEventKey { PhysicalKeycode = code });
            if (buttons.TryGetValue(suffix, out var button)) InputMap.ActionAddEvent(action, new InputEventJoypadButton { ButtonIndex = button });
            if (axes.TryGetValue(suffix, out var axis)) InputMap.ActionAddEvent(action, new InputEventJoypadMotion { Axis = axis.Axis, AxisValue = axis.Value });
            if (suffix == "cry") InputMap.ActionAddEvent(action, new InputEventMouseButton { ButtonIndex = MouseButton.Left });
        }
    }

    public void Setup(CozyMap level, CozySpawn? spawn = null)
    {
        World = level;
        ConfigureInput();
        _flightBounds = level.FlightBounds;
        _ambience = level.Ambience;
        Name = "Player";
        FloorSnapLength = .25f;
        if (level.SupportsSurfaceTraversal) SafeMargin = .015f;
        FloorMaxAngle = .9f;
        CollisionLayer = 2;
        CollisionMask = 1;
        AddChild(new CollisionShape3D { Shape = new CapsuleShape3D { Radius = .22f, Height = .6f }, Position = new(0, .3f, 0) });
        BuildCat();
        BuildGull();
        Camera = new Camera3D { Name = "Camera", Fov = 62, KeepAspect = Camera3D.KeepAspectEnum.Height, Near = .08f, Far = 2500 };
        GetParent().AddChild(Camera);
        Camera.Current = true;
        var pose = spawn ?? new CozySpawn(new(-6.4f, 0, .2f), -.08f);
        Position = new(pose.Position.X, Height(pose.Position.X, pose.Position.Z) + pose.Position.Y, pose.Position.Z);
        _lastCatPosition = _registeredSpawn = Position;
        _camYaw = _heading = _moveDirection = pose.Yaw;
        _camPitch = pose.Pitch;
        Mode = pose.Mode == "gull" ? "gull" : "cat";
        string requestedView = "";
        bool cliGull = false, requestedPose = false;
        foreach (string argument in OS.GetCmdlineUserArgs())
        {
            if (argument == "--shot") ShotMode = true;
            if (argument.StartsWith("--pose=", StringComparison.Ordinal))
            {
                string[] values = argument[7..].Split(',');
                if (values.Length == 5)
                {
                    var numbers = values.Select(v => float.Parse(v, CultureInfo.InvariantCulture)).ToArray();
                    requestedPose = true;
                    Position = new(numbers[0], Height(numbers[0], numbers[1]) + numbers[2], numbers[1]);
                    _camYaw = _heading = _moveDirection = numbers[3];
                    _camPitch = numbers[4];
                    _lastCatPosition = Position;
                }
            }
            if (argument.StartsWith("--view=", StringComparison.Ordinal)) requestedView = argument[7..];
            if (argument is "--gull" or "--bird") { Mode = "gull"; cliGull = true; }
        }
        _gull.Visible = Mode == "gull";
        _cat.Visible = Mode == "cat";
        if (Mode == "gull")
        {
            Position += Vector3.Up * 3;
            if (!requestedPose) _camPitch = cliGull ? .18f : pose.Pitch;
        }
        if (requestedView.Length > 0 && World.ScenicViews.ContainsKey(requestedView)) SetView(requestedView);
        else PlaceCamera(.016f, true);
        MenuOpen = !ShotMode;
        AnimateCat(0);
        AnimateGull(0);
    }

    private float Height(float x, float z) => World.HeightAt(x, z);

    public void SetView(string name)
    {
        if (!World.ScenicViews.TryGetValue(name, out var view)) return;
        FixedView = true;
        _cat.Hide();
        _gull.Hide();
        Position = new(view[0], view[2], view[1]);
        Camera.Position = Position + new Vector3(0, 1.6801f, 0);
        Camera.Rotation = new(view[4], view[3], 0);
    }

    private Godot.Collections.Dictionary Ray(Vector3 from, Vector3 to) =>
        GetWorld3D().DirectSpaceState.IntersectRay(PhysicsRayQueryParameters3D.Create(from, to, 1, [GetRid()]));

    private float SupportHeight()
    {
        float ground = Height(Position.X, Position.Z);
        var hit = Ray(Position + Vector3.Up * .45f, new(Position.X, ground - 1, Position.Z));
        return hit.Count > 0 && hit["normal"].AsVector3().Y > .6f ? Mathf.Max(ground, hit["position"].AsVector3().Y) : ground;
    }

    private Vector3 SafeSurfacePosition(Vector3 candidate)
    {
        foreach (var at in new[] { candidate, _lastCatPosition, _registeredSpawn })
        {
            if (!World.Walkable(at.X, at.Z)) continue;
            float ground = Height(at.X, at.Z);
            var hit = Ray(new(at.X, Mathf.Max(at.Y + .5f, ground + .5f), at.Z), new(at.X, ground - 1, at.Z));
            if (hit.Count == 0 || hit["normal"].AsVector3().Y < .6f) continue;
            var support = hit["position"].AsVector3() + Vector3.Up * .025f;
            var clearance = new PhysicsShapeQueryParameters3D
            {
                Shape = new CapsuleShape3D { Radius = .22f, Height = .6f },
                Transform = new(Basis.Identity, support + Vector3.Up * .31f),
                CollisionMask = 1,
                Exclude = [GetRid()]
            };
            if (GetWorld3D().DirectSpaceState.IntersectShape(clearance, 1).Count == 0) return support;
        }
        return _registeredSpawn + Vector3.Up * .05f;
    }

    public void SetMode(string value)
    {
        if (FixedView || Mode == value || value is not ("cat" or "gull")) return;
        if (Mode == "cat") _lastCatPosition = Position;
        Mode = value;
        Velocity = Vector3.Zero;
        if (Mode == "gull")
        {
            if (World.SupportsSurfaceTraversal)
            {
                var launch = new PhysicsShapeQueryParameters3D
                {
                    Shape = new CapsuleShape3D { Radius = .22f, Height = .6f },
                    Transform = new(Basis.Identity, Position + Vector3.Up * .31f),
                    Motion = Vector3.Up * 1.2f,
                    CollisionMask = 1,
                    Exclude = [GetRid()]
                };
                float[] sweep = GetWorld3D().DirectSpaceState.CastMotion(launch);
                Position += Vector3.Up * Mathf.Max(0, sweep[0] * 1.2f - .04f);
            }
            else Position = new(Position.X, Height(Position.X, Position.Z) + 1.2f, Position.Z);
            Velocity = new(0, 1.5f, 0);
            Perched = false;
            _flap = 1;
            PlaySound("cry");
        }
        else
        {
            if (World.SupportsSurfaceTraversal) Position = SafeSurfacePosition(Position);
            else
            {
                if (!World.Walkable(Position.X, Position.Z))
                    Position = World.Walkable(_lastCatPosition.X, _lastCatPosition.Z) ? _lastCatPosition : _registeredSpawn;
                Position = new(Position.X, Height(Position.X, Position.Z), Position.Z);
            }
            Grounded = true;
            Perched = false;
            _camPitch = Mathf.Clamp(_camPitch, .05f, 1);
            _cameraDistance = 4.2f;
        }
        _heading = _camYaw;
        _cat.Visible = Mode == "cat";
        _gull.Visible = Mode == "gull";
        _speed = 0;
        PlaceCamera(.016f, true);
        EmitSignal(SignalName.ModeChanged, Mode);
    }

    public void SetMenu(bool open)
    {
        if (ShotMode || MenuOpen == open) return;
        MenuOpen = open;
        ClearInput();
        Input.MouseMode = !open && MouseCaptureEnabled ? Input.MouseModeEnum.Captured : Input.MouseModeEnum.Visible;
        if (!open && Audio == null) StartAudio();
        EmitSignal(SignalName.MenuChanged, open);
    }

    public void ClearInput()
    {
        _tapUntil.Clear();
        _touchActions.Clear();
        TouchMove = Vector2.Zero;
    }

    public void TouchLook(Vector2 delta)
    {
        if (MenuOpen || ShotMode) return;
        _camYaw += delta.X * .0022f;
        _camPitch = Mathf.Clamp(_camPitch + delta.Y * .0016f, Mode == "gull" ? -1.05f : .05f, Mode == "gull" ? 1.15f : 1);
    }

    public void TouchAction(string action, bool pressed)
    {
        string suffix = action.StartsWith("cozy_", StringComparison.Ordinal) ? action[5..] : action;
        if (MenuOpen || ShotMode) return;
        _touchActions[suffix] = pressed;
        if (!pressed) return;
        switch (suffix)
        {
            case "switch": SetMode(Mode == "cat" ? "gull" : "cat"); break;
            case "pause": SetMenu(true); break;
            case "cry": if (Mode == "gull") PlaySound("cry"); break;
            default: _tapUntil[suffix] = Time.GetTicksMsec() + 100; break;
        }
    }

    public override void _UnhandledInput(InputEvent input)
    {
        if (ShotMode) return;
        if (input is InputEventScreenTouch or InputEventScreenDrag)
        {
            MouseCaptureEnabled = false;
            Input.MouseMode = Input.MouseModeEnum.Visible;
        }
        if (input.IsActionPressed("cozy_pause"))
        {
            SetMenu(!MenuOpen);
            GetViewport().SetInputAsHandled();
            return;
        }
        if (MenuOpen) return;
        if (input is InputEventKey or InputEventJoypadButton && input.IsPressed() && !input.IsEcho())
            foreach (string action in new[] { "move_left", "move_right", "move_forward", "move_back", "jump", "descend", "sprint" })
                if (input.IsActionPressed("cozy_" + action)) _tapUntil[action] = Time.GetTicksMsec() + 100;
        if (input.IsActionPressed("cozy_switch"))
        {
            SetMode(Mode == "cat" ? "gull" : "cat");
            GetViewport().SetInputAsHandled();
        }
        else if (input is InputEventMouseMotion motion && Input.MouseMode == Input.MouseModeEnum.Captured) TouchLook(motion.Relative);
        else if (input.IsActionPressed("cozy_cry") && Mode == "gull") PlaySound("cry");
    }

    public override void _Notification(int what)
    {
        if (what == NotificationApplicationFocusOut && IsInsideTree() && !ShotMode) SetMenu(true);
    }

    private float Strength(string action)
    {
        if (MenuOpen || ShotMode) return 0;
        bool held = _touchActions.GetValueOrDefault(action) || _tapUntil.GetValueOrDefault(action) > Time.GetTicksMsec();
        return Mathf.Max(Input.GetActionStrength("cozy_" + action), held ? 1 : 0);
    }
    private bool Held(string action) => Strength(action) > .2f;
    private Vector2 MovementInput() => MenuOpen || ShotMode ? Vector2.Zero :
        new(Mathf.Clamp(Strength("move_right") - Strength("move_left") + TouchMove.X, -1, 1),
            Mathf.Clamp(Strength("move_back") - Strength("move_forward") + TouchMove.Y, -1, 1));

    public override void _PhysicsProcess(double delta)
    {
        if (World == null || FixedView || MenuOpen) return;
        float dt = (float)Math.Min(delta, .05);
        if (!ShotMode)
        {
            var look = Input.GetVector("cozy_look_left", "cozy_look_right", "cozy_look_up", "cozy_look_down", .2f);
            _camYaw += look.X * 2.2f * dt;
            _camPitch = Mathf.Clamp(_camPitch + look.Y * 1.6f * dt, Mode == "gull" ? -1.05f : .05f, Mode == "gull" ? 1.15f : 1);
        }
        _elapsed = ShotMode ? 3 : _elapsed + dt;
        if (Mode == "cat") UpdateCat(dt);
        else UpdateGull(dt);
        PlaceCamera(dt);
    }

    public override void _ExitTree()
    {
        ClearInput();
        StopAudio();
    }

    private void UpdateCat(float dt)
    {
        var input = MovementInput();
        float horizontal = input.X, forward = -input.Y;
        bool moving = horizontal != 0 || forward != 0;
        float turn = Mathf.Clamp(Mathf.Wrap(_camYaw - _heading, -Mathf.Pi, Mathf.Pi) * 12, -9, 9);
        _heading += turn * dt;
        float targetSpeed = moving ? (Held("sprint") ? 6.4f : 3.6f) * Mathf.Min(1, input.Length()) : 0;
        _speed = Mathf.Lerp(_speed, targetSpeed, Mathf.Min(1, (targetSpeed > _speed ? 5 : 8) * dt));
        if (moving) _moveDirection = _camYaw + Mathf.Atan2(horizontal, forward);
        else if (_speed < .05f) _speed = 0;
        var movement = new Vector3(Mathf.Sin(_moveDirection), 0, -Mathf.Cos(_moveDirection)) * _speed;
        var proposed = Position + movement * dt;
        if (!World.Walkable(proposed.X, proposed.Z))
        {
            if (World.Walkable(proposed.X, Position.Z)) movement.Z = 0;
            else if (World.Walkable(Position.X, proposed.Z)) movement.X = 0;
            else movement = Vector3.Zero;
        }
        if (Grounded && Height(proposed.X, proposed.Z) - Position.Y > .7f) movement = Vector3.Zero;
        Velocity = new(movement.X, Velocity.Y - 22 * dt, movement.Z);
        if (Held("jump") && Grounded)
        {
            Velocity = new(Velocity.X, 6.2f, Velocity.Z);
            Grounded = false;
            PlaySound("meow");
        }
        MoveAndSlide();
        float floorY = Height(Position.X, Position.Z);
        if (Position.Y <= floorY)
        {
            if (!Grounded) PlaySound("step");
            Position = new(Position.X, floorY, Position.Z);
            Velocity = new(Velocity.X, 0, Velocity.Z);
            Grounded = true;
        }
        else if (IsOnFloor()) Grounded = true;
        else if (Position.Y - floorY > .05f) Grounded = false;
        if (Grounded && _speed > .3f)
        {
            int oldStep = (int)_stepPhase;
            _stepPhase += dt * (6 + _speed * 2.2) / Math.PI;
            if ((int)_stepPhase != oldStep) PlaySound("step");
        }
        var direction = new Vector3(Mathf.Sin(_heading), 0, -Mathf.Cos(_heading)) * .4f;
        float slope = Height(Position.X + direction.X, Position.Z + direction.Z) - Height(Position.X - direction.X, Position.Z - direction.Z);
        if (World.SupportsSurfaceTraversal && IsOnFloor())
        {
            var normal = GetFloorNormal();
            slope = -2 * (normal.X * direction.X + normal.Z * direction.Z) / Mathf.Max(.1f, normal.Y);
        }
        _cat.Rotation = new(-Mathf.Atan2(slope, .8f) * .8f, Mathf.Pi - _heading, Mathf.Clamp(turn * .03f, -.25f, .25f) * Mathf.Min(1, _speed / 3));
        AnimateCat(dt);
    }

    private void UpdateGull(float dt)
    {
        var input = MovementInput();
        float forward = -input.Y, lateral = input.X;
        bool climb = Held("jump"), descend = Held("descend"), boost = Held("sprint");
        bool activeInput = forward != 0 || lateral != 0 || climb || descend;
        float responsePitch = Mathf.Sign(_camPitch) * Mathf.Max(0, Mathf.Abs(_camPitch) - .16f) / .84f;
        float vertical = -Mathf.Sin(responsePitch * 1.35f);
        float horizontal = Mathf.Sqrt(Mathf.Max(0, 1 - vertical * vertical));
        var direction = new Vector3(Mathf.Sin(_camYaw) * horizontal, vertical, -Mathf.Cos(_camYaw) * horizontal);
        var flatDirection = new Vector3(Mathf.Sin(_camYaw), 0, -Mathf.Cos(_camYaw));
        if (Perched && World.SupportsSurfaceTraversal && Position.Y - GullFloor() > .65f)
        {
            Perched = false;
            Velocity = new(Velocity.X, -.6f, Velocity.Z);
        }
        if (Perched)
        {
            if (forward > 0 || climb)
            {
                Perched = false;
                Velocity = flatDirection * 2.5f + Vector3.Up * 3.2f;
                _flap = 1;
                PlaySound("cry");
            }
            else
            {
                _heading += Mathf.Clamp(Mathf.Wrap(_camYaw - _heading, -Mathf.Pi, Mathf.Pi) * 4, -3, 3) * dt;
                _birdPitch = Mathf.Lerp(_birdPitch, 0, Mathf.Min(1, dt * 6));
                _bank = Mathf.Lerp(_bank, 0, Mathf.Min(1, dt * 6));
                Position = new(Position.X, GullFloor(), Position.Z);
                AnimateGull(dt);
                return;
            }
        }
        float targetSpeed = boost ? 17 : 9.5f;
        var target = Vector3.Zero;
        if (forward > 0) target += direction * targetSpeed * forward;
        else if (forward < 0) target += flatDirection * 3.5f * forward;
        target += new Vector3(Mathf.Cos(_camYaw), 0, Mathf.Sin(_camYaw)) * lateral * (forward > 0 ? 5 : 6);
        if (climb) target.Y += forward > 0 ? 4.5f : 5.5f;
        if (descend) target.Y -= 6;
        if (!activeInput) target = new(Mathf.Sin(_heading) * 3, -.9f, -Mathf.Cos(_heading) * 3);
        Velocity = Velocity.Lerp(target, Mathf.Min(1, dt * (activeInput ? 3.2f : .9f)));
        if (forward > 0 && direction.Y < -.3f) Velocity += Vector3.Up * direction.Y * 4 * dt;
        if (World.SupportsSurfaceTraversal || Position.Y - Height(Position.X, Position.Z) < 2.2f) MoveAndSlide();
        else Position += Velocity * dt;
        Position = new(Mathf.Clamp(Position.X, _flightBounds.Position.X, _flightBounds.End.X), Position.Y,
            Mathf.Clamp(Position.Z, _flightBounds.Position.Z, _flightBounds.End.Z));
        if (Position.Y > _flightBounds.End.Y)
        {
            Position = new(Position.X, _flightBounds.End.Y, Position.Z);
            Velocity = new(Velocity.X, Mathf.Min(0, Velocity.Y), Velocity.Z);
        }
        float floorY = GullFloor();
        float horizontalSpeed = new Vector2(Velocity.X, Velocity.Z).Length();
        if (Position.Y <= floorY)
        {
            Position = new(Position.X, floorY, Position.Z);
            if (Velocity.Y < 0 && horizontalSpeed < 4.5f && !climb && forward <= 0)
            {
                Perched = true;
                Velocity = Vector3.Zero;
                PlaySound("step");
            }
            else Velocity = new(Velocity.X, horizontalSpeed < 1 ? 1.5f : Mathf.Max(0, Velocity.Y), Velocity.Z);
        }
        float flapTarget = Velocity.Y > .4f || climb ? 1 : forward > 0 && horizontalSpeed < targetSpeed * .8f ? .7f : forward > 0 && !boost ? .25f : 0;
        _flap = Mathf.Lerp(_flap, flapTarget, Mathf.Min(1, dt * 5));
        int oldFlap = (int)_stepPhase;
        if (_flap > .45f) _stepPhase += dt * (1.8 + _flap * 2.2);
        if (oldFlap != (int)_stepPhase) PlaySound("wing");
        float flightSpeed = Velocity.Length();
        float targetHeading = flightSpeed > 1.5f ? Mathf.Atan2(Velocity.X, -Velocity.Z) : _camYaw;
        float turn = Mathf.Clamp(Mathf.Wrap(targetHeading - _heading, -Mathf.Pi, Mathf.Pi) * 6, -4.5f, 4.5f);
        _heading += turn * dt;
        float climbAngle = flightSpeed > 1 ? Mathf.Asin(Mathf.Clamp(Velocity.Y / flightSpeed, -1, 1)) : 0;
        _birdPitch = Mathf.Lerp(_birdPitch, Mathf.Clamp(climbAngle, -.9f, .7f), Mathf.Min(1, dt * 4));
        float targetBank = Mathf.Clamp(-turn * .22f - lateral * .35f, -.9f, .9f) * Mathf.Min(1, flightSpeed / 4);
        _bank = Mathf.Lerp(_bank, targetBank, Mathf.Min(1, dt * 4));
        AnimateGull(dt);
    }

    private float GullFloor()
    {
        float ground = Mathf.Max(World.SupportsSurfaceTraversal ? SupportHeight() : Height(Position.X, Position.Z), _flightBounds.Position.Y + .05f);
        return World.WaterSupportHeight(Position.X, Position.Z, ground) + .17f;
    }

    public void PlaceCamera(float dt, bool immediate = false)
    {
        bool bird = Mode == "gull";
        var focus = Position + new Vector3(0, bird ? .25f : .5f, 0);
        var offset = new Vector3(-Mathf.Sin(_camYaw) * Mathf.Cos(_camPitch), Mathf.Sin(_camPitch), Mathf.Cos(_camYaw) * Mathf.Cos(_camPitch));
        float distance = bird ? Perched ? 3.4f : 4.5f : 4.2f;
        if ((!bird || World.SupportsSurfaceTraversal) && IsInsideTree())
        {
            var hit = Ray(focus, focus + offset * distance);
            if (hit.Count > 0) distance = Mathf.Clamp(focus.DistanceTo(hit["position"].AsVector3()) - .55f, World.SupportsSurfaceTraversal ? .35f : 1.3f, 4.2f);
            _cameraDistance = immediate ? distance : Mathf.Lerp(_cameraDistance, distance, Mathf.Min(1, dt * (distance < _cameraDistance ? 12 : 2)));
            distance = _cameraDistance;
        }
        var destination = focus + offset * distance + new Vector3(0, bird ? .315f : .385f, 0);
        float clearance = bird ? Perched ? 1.6f : .7f : 1.1f;
        destination.Y = Mathf.Max(destination.Y, Mathf.Max(Height(destination.X, destination.Z), _flightBounds.Position.Y) + clearance);
        Camera.Position = immediate ? destination : Camera.Position.Lerp(destination, 1 - Mathf.Exp(-dt * (bird ? 5.5f : 6.5f)));
        if (World.SupportsSurfaceTraversal)
        {
            var obstruction = Ray(focus, Camera.Position);
            if (obstruction.Count > 0)
            {
                var point = obstruction["position"].AsVector3();
                Camera.Position = point + (focus - point).Normalized() * .14f;
            }
        }
        _cameraLook = immediate ? focus : _cameraLook.Lerp(focus, 1 - Mathf.Exp(-dt * 9));
        Camera.LookAt(_cameraLook);
        Camera.Rotation += new Vector3(0, 0, bird ? _bank * .12f : (float)Math.Sin(_elapsed * 9) * .0025f * Mathf.Min(1, _speed / 4));
    }
}
