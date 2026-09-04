extends RefCounted
class_name CozyUITheme

const INK := Color("254d4b")
const MUTED := Color("61726b")
const PAPER := Color("fffdf5")
const GOLD := Color("bb8a35")

static func body_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Helvetica Neue", "Noto Sans", "DejaVu Sans"])
	return font

static func title_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Georgia", "Noto Serif", "DejaVu Serif"])
	return font

static func panel(color: Color, radius: int = 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style

static func button_style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := panel(color, 12)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	return style

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		theme.set_color("font_" + state + "_color", "Button", PAPER)
	theme.set_color("font_focus_color", "Button", PAPER)
	theme.set_color("font_disabled_color", "Button", Color("9daaa2"))
	theme.set_stylebox("normal", "Button", button_style(INK))
	theme.set_stylebox("hover", "Button", button_style(Color("346661")))
	theme.set_stylebox("pressed", "Button", button_style(Color("193d3a")))
	theme.set_stylebox("disabled", "Button", button_style(Color("e1e6db")))
	var focus := panel(Color.TRANSPARENT, 14)
	focus.border_color = GOLD
	focus.set_border_width_all(3)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	theme.set_stylebox("focus", "Button", focus)
	theme.set_constant("outline_size", "Button", 0)
	return theme

static func secondary(button: Button) -> void:
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_stylebox_override("normal", button_style(Color("f7f5e9"), Color("b8c4b4")))
	button.add_theme_stylebox_override("hover", button_style(Color("e7eddd"), Color("98af9f")))
	button.add_theme_stylebox_override("pressed", button_style(Color("d9e3d0"), Color("809d8f")))
