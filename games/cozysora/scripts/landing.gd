extends Control
class_name CozyLanding

signal play_requested(map_id: StringName)
signal settings_requested

const UI = preload("res://scripts/ui_theme.gd")
const PREVIEW_SHADER = preload("res://shaders/landing_preview.gdshader")

var _scroll: ScrollContainer
var _margin: MarginContainer
var _column: VBoxContainer
var _header: HBoxContainer
var _heading: VBoxContainer
var _title: Label
var _welcome: Label
var _settings: Button
var _cards: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _footer: Label
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.make_theme()
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/landing_background.gdshader")
	background.material = material
	add_child(background)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	_margin = MarginContainer.new()
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_margin)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 28)
	_margin.add_child(_column)
	_column.resized.connect(_layout)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 16)
	_column.add_child(_header)
	_heading = VBoxContainer.new()
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.add_theme_constant_override("separation", 4)
	_header.add_child(_heading)
	_title = _label("Cozy Sora", 49)
	_title.add_theme_font_override("font", UI.title_font())
	_heading.add_child(_title)
	_welcome = _label("Slow down. See where summer takes you.", 17, UI.MUTED)
	_welcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_child(_welcome)
	_settings = Button.new()
	_settings.text = "Settings"
	_settings.custom_minimum_size = Vector2(112, 48)
	_settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_settings.focus_mode = Control.FOCUS_ALL
	_settings.pressed.connect(func(): settings_requested.emit())
	UI.secondary(_settings)
	_header.add_child(_settings)
	resized.connect(_layout)

func setup(maps: Array) -> void:
	for item in _cards:
		item.panel.queue_free()
	_cards.clear()
	_buttons.clear()
	if is_instance_valid(_footer):
		_footer.queue_free()
	for destination in maps:
		_add_destination(destination)
	_footer = _label("More destinations coming soon", 14, UI.MUTED)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.custom_minimum_size.y = 32
	_column.add_child(_footer)
	_layout()
	_link_focus()
	focus_default.call_deferred()

func _add_destination(destination: Resource) -> void:
	var card := Panel.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := UI.panel(UI.PAPER, 20)
	style.shadow_color = Color(0.13, 0.24, 0.20, 0.10)
	style.shadow_size = 24
	style.shadow_offset = Vector2(0, 10)
	style.border_color = Color("dce3d3")
	style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", style)
	_column.add_child(card)
	var preview := TextureRect.new()
	preview.texture = destination.preview
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview_material := ShaderMaterial.new()
	preview_material.shader = PREVIEW_SHADER
	preview.material = preview_material
	card.add_child(preview)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	card.add_child(content)
	content.minimum_size_changed.connect(_layout.call_deferred)
	var eyebrow := _label(destination.subtitle.to_upper(), 12, Color("8d743f"))
	eyebrow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(eyebrow)
	var title := _label(destination.title, 36)
	title.add_theme_font_override("font", UI.title_font())
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(title)
	var description := _label(destination.description, 17, UI.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_constant_override("line_spacing", 5)
	content.add_child(description)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var play := Button.new()
	play.text = "Play   →"
	play.custom_minimum_size.y = 56
	play.focus_mode = Control.FOCUS_ALL
	play.add_theme_font_size_override("font_size", 18)
	play.pressed.connect(func():
		if not _busy:
			play_requested.emit(destination.id)
	)
	content.add_child(play)
	var hint := _label("On little paws. On open wings.", 13, UI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)
	_buttons.append(play)
	_cards.append({"panel": card, "preview": preview, "material": preview_material,
		"content": content, "title": title, "description": description,
		"eyebrow": eyebrow, "hint": hint, "spacer": spacer})

func _label(text: String, font_size: int, color: Color = UI.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _layout() -> void:
	if not is_instance_valid(_column):
		return
	var viewport_size := size
	var compact := viewport_size.x < 720
	var short_landscape := not compact and viewport_size.y < 520
	var short_portrait := compact and viewport_size.y < 720
	var short_view := short_landscape or short_portrait
	var inset := 24 if compact else int(clampf((viewport_size.x - 1160.0) * 0.5, 40.0, 320.0))
	var top := 16 if short_view else 30 if compact or viewport_size.y < 600 else int(clampf((viewport_size.y - 590.0 - maxf(0.0, _cards.size() - 1) * 438.0) * 0.5, 44.0, 260.0))
	_margin.add_theme_constant_override("margin_left", inset)
	_margin.add_theme_constant_override("margin_right", inset)
	_margin.add_theme_constant_override("margin_top", top)
	_margin.add_theme_constant_override("margin_bottom", 16 if short_view else 28)
	_column.add_theme_constant_override("separation", 12 if short_view else 26 if compact else 30)
	_title.add_theme_font_size_override("font_size", 28 if short_portrait else 34 if short_landscape else 36 if compact else 49)
	_welcome.visible = not short_view
	_welcome.add_theme_font_size_override("font_size", 14 if compact or short_landscape else 17)
	if is_instance_valid(_footer):_footer.custom_minimum_size.y = 24 if short_view else 32
	_settings.custom_minimum_size.x = 94 if compact else 112
	_settings.add_theme_font_size_override("font_size", 14 if compact else 16)
	var available_width := _column.size.x if _column.size.x > 1.0 else viewport_size.x - inset * 2
	for item in _cards:
		var card: Panel = item.panel
		var preview: TextureRect = item.preview
		var content: VBoxContainer = item.content
		var title: Label = item.title
		title.add_theme_font_size_override("font_size", 26 if short_portrait else 28 if short_landscape else 30 if compact else 36)
		var content_inset := 20.0 if short_view else 24.0 if compact else 34.0
		var picture_width := available_width if compact else available_width * (0.46 if short_landscape else 0.57)
		var picture_height := clampf(available_width * 0.5, 120.0, 180.0) if short_portrait else clampf(available_width * 0.63, 195.0, 300.0) if compact else 250.0 if short_landscape else 408.0
		var content_width := available_width - 2.0 * content_inset if compact else available_width - picture_width - 2.0 * content_inset
		content.size.x = maxf(160.0, content_width)
		item.spacer.visible = not compact and not short_landscape
		item.hint.visible = not short_view
		item.description.add_theme_font_size_override("font_size", 15 if short_view else 17)
		content.add_theme_constant_override("separation", 12 if short_view else 14 if compact else 18)
		var content_height := maxf(content.get_combined_minimum_size().y, 0.0 if short_view else 302.0 if compact else 340.0)
		if not compact:
			picture_height = maxf(250.0 if short_landscape else 408.0, content_height + 2.0 * content_inset)
		card.custom_minimum_size.y = picture_height + content_height + 2.0 * content_inset if compact else picture_height
		preview.position = Vector2.ZERO
		preview.size = Vector2(picture_width, picture_height)
		item.material.set_shader_parameter("panel_size", preview.size)
		item.material.set_shader_parameter("corners", Vector4(20, 20, 0, 0) if compact else Vector4(20, 0, 0, 20))
		content.position = Vector2(content_inset, picture_height + content_inset) if compact else Vector2(picture_width + content_inset, content_inset)
		content.size = Vector2(maxf(160.0, content_width), content_height if compact else picture_height - 2.0 * content_inset)

func _link_focus() -> void:
	var controls: Array[Button] = [_settings]
	controls.append_array(_buttons)
	for i in controls.size():
		var current := controls[i]
		var previous := controls[posmod(i - 1, controls.size())]
		var next := controls[(i + 1) % controls.size()]
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_neighbor_left = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_neighbor_right = current.get_path_to(next)
		current.focus_previous = current.get_path_to(previous)
		current.focus_next = current.get_path_to(next)

func focus_default() -> void:
	if not _busy and not _buttons.is_empty():
		_buttons[0].grab_focus()
		# Let variable-height destination cards settle before showing the welcome header.
		await get_tree().process_frame
		await get_tree().process_frame
		if not _busy and is_visible_in_tree() and get_viewport().gui_get_focus_owner()==_buttons[0]:_scroll.scroll_vertical=0

func set_busy(value: bool) -> void:
	_busy = value
	_settings.disabled = value
	for button in _buttons:
		button.disabled = value
