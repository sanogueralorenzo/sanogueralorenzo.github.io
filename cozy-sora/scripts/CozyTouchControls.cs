using Godot;

namespace CozySora;

public partial class CozyTouchControls : Control
{
    public CozyPlayer? Player { get; set; }
    private int _moveFinger = -999, _lookFinger = -999;
    private readonly Dictionary<int, string> _held = new();
    private Vector2 _origin, _stick;
    private Dictionary<string, Vector2> _actions = new();
    private readonly SystemFont _font = new();

    public override void _Ready()
    {
        SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
        MouseFilter = MouseFilterEnum.Ignore;
        Resized += Layout;
        VisibilityChanged += Reset;
        Layout();
    }

    private void Layout()
    {
        float widthFactor = Mathf.Clamp((Size.X - 320) / 70, 0, 1);
        _origin = new(Mathf.Lerp(70, 94, widthFactor), Size.Y - 96);
        float outerX = Size.X - Mathf.Lerp(48, 74, widthFactor);
        float innerX = Size.X - Mathf.Lerp(114, 151, widthFactor);
        _actions = new()
        {
            ["jump"] = new(outerX, Size.Y - 85),
            ["sprint"] = new(innerX, Size.Y - 80),
            ["descend"] = new(innerX, Size.Y - 151),
            ["switch"] = new(outerX, Size.Y - 162)
        };
        QueueRedraw();
    }

    private void Reset()
    {
        _moveFinger = _lookFinger = -999;
        _held.Clear();
        _stick = Vector2.Zero;
        if (IsInstanceValid(Player)) Player!.ClearInput();
        QueueRedraw();
    }

    public override void _Input(InputEvent input)
    {
        if (!Visible || !IsInstanceValid(Player) || Player!.MenuOpen) return;
        if (input is InputEventMouse && input.Device == InputEvent.DeviceIdEmulation) return;
        switch (input)
        {
            case InputEventScreenTouch touch: Contact(touch.Index, touch.Position, touch.Pressed); break;
            case InputEventScreenDrag drag: Drag(drag.Index, drag.Position, drag.Relative); break;
            case InputEventMouseButton { ButtonIndex: MouseButton.Left } mouse: Contact(-1, mouse.Position, mouse.Pressed); break;
            case InputEventMouseMotion motion when (motion.ButtonMask & MouseButtonMask.Left) != 0: Drag(-1, motion.Position, motion.Relative); break;
        }
    }

    private void Contact(int id, Vector2 at, bool pressed)
    {
        if (!pressed)
        {
            if (id == _moveFinger) { _moveFinger = -999; _stick = Vector2.Zero; Player!.TouchMove = Vector2.Zero; }
            if (id == _lookFinger) _lookFinger = -999;
            if (_held.Remove(id, out var held)) Player!.TouchAction(held, false);
            QueueRedraw();
            return;
        }
        if (at.Y < 80) return;
        foreach (var (action, point) in _actions)
        {
            if (at.DistanceTo(point) >= 32) continue;
            _held[id] = action;
            Player!.TouchAction(action, true);
            GetViewport().SetInputAsHandled();
            QueueRedraw();
            return;
        }
        if (at.DistanceTo(_origin) < 85 && _moveFinger == -999)
        {
            _moveFinger = id;
            Drag(id, at, Vector2.Zero);
        }
        else if (at.X > Size.X * .45f && _lookFinger == -999)
        {
            _lookFinger = id;
            GetViewport().SetInputAsHandled();
        }
    }

    private void Drag(int id, Vector2 at, Vector2 delta)
    {
        if (id == _moveFinger)
        {
            _stick = (at - _origin).LimitLength(48);
            Player!.TouchMove = _stick / 48;
            QueueRedraw();
            GetViewport().SetInputAsHandled();
        }
        else if (id == _lookFinger)
        {
            Player!.TouchLook(delta);
            GetViewport().SetInputAsHandled();
        }
    }

    public override void _Draw()
    {
        if (!Visible) return;
        DrawCircle(_origin, 64, new(.05f, .15f, .16f, .48f));
        DrawArc(_origin, 64, 0, Mathf.Tau, 64, new(1, 1, .9f, .45f), 2, true);
        DrawCircle(_origin + _stick, 25, new(.95f, .96f, .85f, .65f));
        foreach (var (action, at) in _actions)
        {
            DrawCircle(at, 30, _held.ContainsValue(action) ? new(.12f, .3f, .3f, .88f) : new(.05f, .15f, .16f, .60f));
            DrawArc(at, 30, 0, Mathf.Tau, 40, new(1, 1, .9f, .55f), 1.5f, true);
            string text = action switch
            {
                "jump" => IsInstanceValid(Player) && Player!.Mode == "gull" ? "Climb" : "Jump",
                "descend" => "Drop",
                "sprint" => "Boost",
                "switch" => "Switch",
                _ => ""
            };
            float width = _font.GetStringSize(text, HorizontalAlignment.Left, -1, 14).X;
            DrawString(_font, at + new Vector2(-width * .5f, 5), text, HorizontalAlignment.Left, -1, 14, new Color("fffdf5"));
        }
    }
}
