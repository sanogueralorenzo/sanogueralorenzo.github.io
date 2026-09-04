extends CanvasLayer
## Cozy Sora title card, built with responsive engine controls and system fonts.
var player: CozyPlayer
var root: Control
var panel: PanelContainer
var cat_button: Button
var gull_button: Button
var tip: Label
var dot: Panel

func setup(character: CozyPlayer) -> void:
	player = character
	layer = 12
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Hiragino Sans", "Noto Sans JP", "Helvetica Neue", "Arial"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	root.theme = theme
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_panel_input)
	panel.add_theme_stylebox_override("panel", _style(Color(0.039, 0.094, 0.118, 0.72), Color(1, 1, 1, 0.14), 14, 36, 40))
	root.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	var title := _label("Cozy Sora", 34, Color("f4efe4"))
	content.add_child(title)
	var title_spacing := Control.new()
	title_spacing.custom_minimum_size.y = 18
	title_spacing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_spacing)
	var prompt := _label("Click to head out into the summer heat.", 14, Color(0.957, 0.937, 0.894, 0.85))
	prompt.custom_minimum_size.y = 46
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	content.add_child(prompt)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spacer)
	var picker := HBoxContainer.new()
	picker.alignment = BoxContainer.ALIGNMENT_CENTER
	picker.add_theme_constant_override("separation", 10)
	content.add_child(picker)
	cat_button = _button("🐈 Cat")
	gull_button = _button("🕊 Seagull")
	picker.add_child(cat_button)
	picker.add_child(gull_button)
	cat_button.pressed.connect(func(): player.set_mode("cat"))
	gull_button.pressed.connect(func(): player.set_mode("gull"))
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size.y = 18
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(bottom_spacer)
	tip = _label("", 14, Color(0.957, 0.937, 0.894, 0.85))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.y = 24
	content.add_child(tip)
	dot = Panel.new()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dot.offset_left = -2
	dot.offset_top = -2
	dot.offset_right = 2
	dot.offset_bottom = 2
	dot.add_theme_stylebox_override("panel", _style(Color(1, 1, 1, 0.55), Color.TRANSPARENT, 2, 0, 0))
	root.add_child(dot)
	player.mode_changed.connect(_mode_changed)
	player.menu_changed.connect(_menu_changed)
	get_viewport().size_changed.connect(_resize)
	_mode_changed(player.mode)
	_menu_changed(player.menu_open)
	_resize()

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _style(background: Color, border: Color, radius: int, vertical: int, horizontal: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(100, 38)
	button.add_theme_color_override("font_color", Color("f4efe4"))
	button.add_theme_color_override("font_hover_color", Color("f4efe4"))
	button.add_theme_stylebox_override("hover", _style(Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.25), 9, 8, 18))
	button.add_theme_stylebox_override("pressed", _style(Color(1, 0.84, 0.59, 0.3), Color(1, 0.84, 0.59, 0.7), 9, 8, 18))
	return button

func _mode_changed(mode: String) -> void:
	var selected := _style(Color(1, 0.84, 0.59, 0.22), Color(1, 0.84, 0.59, 0.6), 9, 8, 18)
	var normal := _style(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.18), 9, 8, 18)
	cat_button.add_theme_stylebox_override("normal", selected if mode == "cat" else normal)
	gull_button.add_theme_stylebox_override("normal", selected if mode == "gull" else normal)
	if mode == "cat":
		tip.text = "W A S D  move  ·  mouse look  ·  Shift  sprint  ·  Space  jump & meow  ·  Tab  become the seagull  ·  Esc  release"
	else:
		tip.text = "W  fly where you look  ·  A D  bank  ·  S  brake  ·  Space  climb  ·  C  drop  ·  Shift  boost  ·  click to cry  ·  Tab  become the cat  ·  Esc  release"
	_resize()

func _menu_changed(open: bool) -> void:
	panel.visible = open
	dot.visible = not open

func _panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		player.set_menu(false)
		panel.accept_event()

func _resize() -> void:
	if panel == null: return
	var viewport_size := get_viewport().get_visible_rect().size
	var width := minf(972, viewport_size.x - 48)
	panel.offset_left = -width / 2
	panel.offset_right = width / 2
	var height := 292.0 if width > 650 else 340.0
	panel.offset_top = -height / 2
	panel.offset_bottom = height / 2
