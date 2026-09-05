class_name CozyPlayer
extends CharacterBody3D
## Procedural cat and seagull characters, locomotion, camera, and synthesized audio.
signal mode_changed(mode: String)
signal menu_changed(open: bool)

var world: Node3D
var camera: Camera3D
var cat: Node3D
var gull: Node3D
var cat_body: Node3D
var cat_head: Node3D
var cat_legs: Array = []
var cat_tail: Array[Node3D] = []
var gull_body: Node3D
var gull_head: Node3D
var gull_tail: Node3D
var gull_wings: Array = []
var gull_legs: Array[Node3D] = []
var mode := "cat"
var menu_open := true
var shot_mode := false
var fixed_view := false
var cam_yaw := -0.08
var cam_pitch := 0.09
var heading := -0.08
var move_direction := -0.08
var speed := 0.0
var grounded := true
var perched := false
var elapsed := 0.0
var gait_phase := 0.0
var step_phase := 0.0
var flap_phase := 0.0
var flap := 0.0
var animated_flap := 0.0
var animated_perch := 1.0
var bird_pitch := 0.0
var bank := 0.0
var camera_distance := 4.2
var camera_look := Vector3.ZERO
var last_cat_position := Vector3(-6.4, 0, 0.2)
var registered_spawn := Vector3.ZERO
var ambience: Dictionary = {}
var audio: AudioStreamPlayer
var audio_playback: AudioStreamGeneratorPlayback
var audio_time := 0.0
var audio_noise := 0.0
var sound_events: Array[Dictionary] = []
var next_bird := 4.0
var _tap_until: Dictionary = {}
var _touch_actions: Dictionary = {}
var _materials: Dictionary = {}
var touch_move := Vector2.ZERO # Screen-space convention: right +X, backward +Y.
var mouse_capture_enabled := not OS.has_feature("mobile")
var flight_bounds := AABB(Vector3(-135, -30, -95), Vector3(270, 140, 213))

static func configure_input() -> void:
	# Shared bindings are installed once; registry entries and maps never define input.
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE], "descend": [KEY_C, KEY_CTRL], "sprint": [KEY_SHIFT],
		"switch": [KEY_TAB], "pause": [KEY_ESCAPE], "cry": [],
		"look_left": [], "look_right": [], "look_up": [], "look_down": [],
	}
	var buttons := {"jump": JOY_BUTTON_A, "descend": JOY_BUTTON_B, "sprint": JOY_BUTTON_LEFT_SHOULDER, "switch": JOY_BUTTON_Y, "pause": JOY_BUTTON_START, "cry": JOY_BUTTON_X}
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0], "move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0], "look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0], "look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0]}
	for suffix: String in keys:
		var action := "cozy_" + suffix
		if InputMap.has_action(action): continue
		InputMap.add_action(action, 0.2)
		for code: int in keys[suffix]:
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(action, key)
		if buttons.has(suffix):
			var button := InputEventJoypadButton.new()
			button.button_index = buttons[suffix]
			InputMap.action_add_event(action, button)
		if axes.has(suffix):
			var axis := InputEventJoypadMotion.new()
			axis.axis = axes[suffix][0]
			axis.axis_value = axes[suffix][1]
			InputMap.action_add_event(action, axis)
		if suffix == "cry":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			InputMap.action_add_event(action, mouse)

func setup(level: Node3D, spawn: Dictionary = {}) -> void:
	world = level
	configure_input()
	flight_bounds = world.flight_bounds
	ambience = world.ambience
	name = "Player"
	floor_snap_length = 0.25
	# Small capsules need room to recover cleanly from Harbor’s sloped mesh seams.
	if world.supports_surface_traversal: safe_margin = 0.015
	floor_max_angle = 0.9
	collision_layer = 2
	collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.22
	shape.height = 0.6
	collision.shape = shape
	collision.position.y = 0.3
	add_child(collision)
	_build_cat()
	_build_gull()
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 62.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.08
	camera.far = 2500
	get_parent().add_child(camera)
	camera.current = true
	var spawn_position: Vector3 = spawn.get("position", Vector3(-6.4, 0, 0.2))
	position = Vector3(spawn_position.x, _height(spawn_position.x, spawn_position.z) + spawn_position.y, spawn_position.z)
	last_cat_position = position
	registered_spawn = position
	cam_yaw = float(spawn.get("yaw", -0.08))
	cam_pitch = float(spawn.get("pitch", 0.09))
	heading = cam_yaw
	move_direction = cam_yaw
	mode = "gull" if spawn.get("mode", "cat") == "gull" else "cat"
	var requested_view := ""
	var cli_gull := false
	for argument in OS.get_cmdline_user_args():
		if argument == "--shot": shot_mode = true
		if argument.begins_with("--view="): requested_view = argument.trim_prefix("--view=")
		if argument == "--gull" or argument == "--bird":
			mode = "gull"
			cli_gull = true
	gull.visible = mode == "gull"
	cat.visible = mode == "cat"
	if mode == "gull":
		position.y += 3.0
		cam_pitch = 0.18 if cli_gull else float(spawn.get("pitch", 0.18))
	if not requested_view.is_empty() and world.scenic_views.has(requested_view):
		set_view(requested_view)
	else:
		_place_camera(0.016, true)
	menu_open = not shot_mode
	_animate_cat(0)
	_animate_gull(0)

func _height(x: float, z: float) -> float:
	return float(world.height_at(x, z))

func set_view(view_name: String) -> void:
	if not world.scenic_views.has(view_name): return
	var view: Array = world.scenic_views[view_name]
	fixed_view = true
	cat.hide()
	gull.hide()
	position = Vector3(view[0], view[2], view[1])
	camera.position = position + Vector3(0, 1.6801, 0)
	camera.rotation = Vector3(view[4], view[3], 0)

func _support_height() -> float:
	var ground := _height(position.x, position.z)
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 0.45, Vector3(position.x, ground - 1, position.z), 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.normal.y > 0.6:return maxf(ground, hit.position.y)
	return ground

func _safe_surface_position(candidate: Vector3) -> Vector3:
	for at: Vector3 in [candidate, last_cat_position, registered_spawn]:
		if not world.walkable(at.x, at.z):continue
		var ground := _height(at.x, at.z)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(at.x, maxf(at.y + .5, ground + .5), at.z), Vector3(at.x, ground - 1, at.z), 1, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < .6:continue
		var support: Vector3 = hit.position + Vector3.UP * .025
		var clearance := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new();capsule.radius = .22;capsule.height = .6
		clearance.shape = capsule;clearance.transform.origin = support + Vector3.UP * .31
		clearance.collision_mask = 1;clearance.exclude = [get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(clearance, 1).is_empty():return support
	return registered_spawn + Vector3.UP * .05

func set_mode(value: String) -> void:
	if fixed_view or mode == value or value not in ["cat", "gull"]: return
	if mode == "cat": last_cat_position = position
	mode = value
	velocity = Vector3.ZERO
	if mode == "gull":
		if world.supports_surface_traversal:
			var launch := PhysicsShapeQueryParameters3D.new()
			var capsule := CapsuleShape3D.new();capsule.radius=.22;capsule.height=.6
			launch.shape=capsule;launch.transform.origin=position+Vector3.UP*.31
			launch.motion=Vector3.UP*1.2;launch.collision_mask=1;launch.exclude=[get_rid()]
			var sweep := get_world_3d().direct_space_state.cast_motion(launch)
			position.y += maxf(0,sweep[0]*1.2-.04)
		else:position.y = _height(position.x, position.z) + 1.2
		velocity.y = 1.5
		perched = false
		flap = 1
		_play_sound("cry")
	else:
		if world.supports_surface_traversal:
			position = _safe_surface_position(position)
		else:
			if not world.walkable(position.x, position.z): position = last_cat_position
			position.y = _height(position.x, position.z)
		grounded = true
		cam_pitch = clampf(cam_pitch, 0.05, 1)
		camera_distance = 4.2
	heading = cam_yaw
	cat.visible = mode == "cat"
	gull.visible = mode == "gull"
	speed = 0
	_place_camera(0.016, true)
	mode_changed.emit(mode)

func set_menu(open: bool) -> void:
	if shot_mode or menu_open == open: return
	menu_open = open
	clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not open and mouse_capture_enabled else Input.MOUSE_MODE_VISIBLE
	if not open and audio == null: _start_audio()
	menu_changed.emit(open)

func clear_input() -> void:
	_tap_until.clear()
	_touch_actions.clear()
	touch_move = Vector2.ZERO

func touch_look(delta: Vector2) -> void:
	if menu_open or shot_mode: return
	cam_yaw += delta.x * 0.0022
	cam_pitch = clampf(cam_pitch + delta.y * 0.0016, -1.05 if mode == "gull" else 0.05, 1.15 if mode == "gull" else 1.0)

func touch_action(action: String, pressed: bool) -> void:
	var suffix := action.trim_prefix("cozy_")
	if menu_open or shot_mode: return
	_touch_actions[suffix] = pressed
	if not pressed: return
	match suffix:
		"switch": set_mode("gull" if mode == "cat" else "cat")
		"pause": set_menu(true)
		"cry":
			if mode == "gull": _play_sound("cry")
		_: _tap_until[suffix] = Time.get_ticks_msec() + 100

func _unhandled_input(event: InputEvent) -> void:
	if shot_mode: return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		mouse_capture_enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("cozy_pause"):
		set_menu(not menu_open)
		get_viewport().set_input_as_handled()
		return
	if menu_open: return
	if event is InputEventKey or event is InputEventJoypadButton:
		if event.is_pressed() and not event.is_echo():
			# Retain quick taps across the input/physics boundary.
			for action: String in ["move_left", "move_right", "move_forward", "move_back", "jump", "descend", "sprint"]:
				if event.is_action_pressed("cozy_" + action): _tap_until[action] = Time.get_ticks_msec() + 100
	if event.is_action_pressed("cozy_switch"):
		set_mode("gull" if mode == "cat" else "cat")
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		touch_look(event.relative)
	elif event.is_action_pressed("cozy_cry") and mode == "gull":
		_play_sound("cry")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and not shot_mode:
		set_menu(true)

func _strength(action: String) -> float:
	if menu_open or shot_mode: return 0.0
	return maxf(Input.get_action_strength("cozy_" + action), 1.0 if _touch_actions.get(action, false) or int(_tap_until.get(action, 0)) > Time.get_ticks_msec() else 0.0)

func _held(action: String) -> bool:
	return _strength(action) > 0.2

func _movement_input() -> Vector2:
	if menu_open or shot_mode: return Vector2.ZERO
	return Vector2(clampf(_strength("move_right") - _strength("move_left") + touch_move.x, -1, 1), clampf(_strength("move_back") - _strength("move_forward") + touch_move.y, -1, 1))

func _physics_process(delta: float) -> void:
	if world == null or fixed_view or menu_open: return
	var dt := minf(delta, 0.05)
	if not shot_mode:
		var look := Input.get_vector("cozy_look_left", "cozy_look_right", "cozy_look_up", "cozy_look_down", 0.2)
		cam_yaw += look.x * 2.2 * dt
		cam_pitch = clampf(cam_pitch + look.y * 1.6 * dt, -1.05 if mode == "gull" else 0.05, 1.15 if mode == "gull" else 1.0)
	elapsed = 3.0 if shot_mode else elapsed + dt
	if mode == "cat": _update_cat(dt)
	else: _update_gull(dt)
	_place_camera(dt)

func _exit_tree() -> void:
	clear_input()
	if is_instance_valid(audio): audio.stop()
	audio_playback = null
	sound_events.clear()

func _update_cat(dt: float) -> void:
	var movement_input := _movement_input()
	var horizontal := movement_input.x
	var forward := -movement_input.y
	var moving := horizontal != 0 or forward != 0
	var turn := clampf(wrapf(cam_yaw - heading, -PI, PI) * 12, -9, 9)
	heading += turn * dt
	var target_speed := (6.4 if _held("sprint") else 3.6) * minf(1, movement_input.length()) if moving else 0.0
	speed = lerpf(speed, target_speed, minf(1, (5.0 if target_speed > speed else 8.0) * dt))
	if moving: move_direction = cam_yaw + atan2(horizontal, forward)
	elif speed < 0.05: speed = 0
	var movement := Vector3(sin(move_direction), 0, -cos(move_direction)) * speed
	var proposed := position + movement * dt
	if not world.walkable(proposed.x, proposed.z):
		if world.walkable(proposed.x, position.z): movement.z = 0
		elif world.walkable(position.x, proposed.z): movement.x = 0
		else: movement = Vector3.ZERO
	if grounded and _height(proposed.x, proposed.z) - position.y > 0.7:
		movement = Vector3.ZERO
	velocity.x = movement.x
	velocity.z = movement.z
	velocity.y -= 22.0 * dt
	if _held("jump") and grounded:
		velocity.y = 6.2
		grounded = false
		_play_sound("meow")
	move_and_slide()
	var floor_y := _height(position.x, position.z)
	if position.y <= floor_y:
		if not grounded: _play_sound("step")
		position.y = floor_y
		velocity.y = 0
		grounded = true
	elif is_on_floor(): grounded = true
	elif position.y - floor_y > 0.05: grounded = false
	if grounded and speed > 0.3:
		var old_step := int(step_phase)
		step_phase += dt * (6 + speed * 2.2) / PI
		if int(step_phase) != old_step: _play_sound("step")
	cat.rotation.y = PI - heading
	cat.rotation.z = clampf(turn * 0.03, -0.25, 0.25) * minf(1, speed / 3)
	var direction := Vector3(sin(heading), 0, -cos(heading)) * 0.4
	var slope := _height(position.x + direction.x, position.z + direction.z) - _height(position.x - direction.x, position.z - direction.z)
	if world.supports_surface_traversal and is_on_floor():
		var normal := get_floor_normal()
		slope = -2.0*(normal.x*direction.x+normal.z*direction.z)/maxf(.1,normal.y)
	cat.rotation.x = -atan2(slope, 0.8) * 0.8
	_animate_cat(dt)

func _update_gull(dt: float) -> void:
	var movement_input := _movement_input()
	var forward := -movement_input.y
	var lateral := movement_input.x
	var climb := _held("jump")
	var descend := _held("descend")
	var boost := _held("sprint")
	var active_input := forward != 0 or lateral != 0 or climb or descend
	var response_pitch := signf(cam_pitch) * maxf(0, absf(cam_pitch) - 0.16) / 0.84
	var vertical := -sin(response_pitch * 1.35)
	var horizontal := sqrt(maxf(0, 1 - vertical * vertical))
	var direction := Vector3(sin(cam_yaw) * horizontal, vertical, -cos(cam_yaw) * horizontal)
	var flat_direction := Vector3(sin(cam_yaw), 0, -cos(cam_yaw))
	if perched and world.supports_surface_traversal and position.y-(maxf(_support_height(),flight_bounds.position.y+.05)+.17)>.65:
		perched=false
		velocity.y=-.6
	if perched:
		if forward > 0 or climb:
			perched = false
			velocity = flat_direction * 2.5 + Vector3.UP * 3.2
			flap = 1
			_play_sound("cry")
		else:
			heading += clampf(wrapf(cam_yaw - heading, -PI, PI) * 4, -3, 3) * dt
			bird_pitch = lerpf(bird_pitch, 0, minf(1, dt * 6))
			bank = lerpf(bank, 0, minf(1, dt * 6))
			position.y = maxf(_support_height() if world.supports_surface_traversal else _height(position.x, position.z), flight_bounds.position.y + 0.05) + 0.17
			_animate_gull(dt)
			return
	var target_speed := 17.0 if boost else 9.5
	var target := Vector3.ZERO
	if forward > 0: target += direction * target_speed * forward
	elif forward < 0: target += flat_direction * 3.5 * forward
	target += Vector3(cos(cam_yaw), 0, sin(cam_yaw)) * lateral * (5 if forward > 0 else 6)
	if climb: target.y += 4.5 if forward > 0 else 5.5
	if descend: target.y -= 6
	if not active_input: target = Vector3(sin(heading) * 3, -0.9, -cos(heading) * 3)
	velocity = velocity.lerp(target, minf(1, dt * (3.2 if active_input else 0.9)))
	if forward > 0 and direction.y < -0.3: velocity.y += direction.y * 4 * dt
	if world.supports_surface_traversal or position.y - _height(position.x, position.z) < 2.2: move_and_slide()
	else: position += velocity * dt
	position.x = clampf(position.x, flight_bounds.position.x, flight_bounds.end.x)
	position.z = clampf(position.z, flight_bounds.position.z, flight_bounds.end.z)
	if position.y > flight_bounds.end.y:
		position.y = flight_bounds.end.y
		velocity.y = minf(0, velocity.y)
	var floor_y := maxf(_support_height() if world.supports_surface_traversal else _height(position.x, position.z), flight_bounds.position.y + 0.05) + 0.17
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if position.y <= floor_y:
		position.y = floor_y
		if velocity.y < 0 and horizontal_speed < 4.5 and not climb and forward <= 0:
			perched = true
			velocity = Vector3.ZERO
			_play_sound("step")
		else:
			velocity.y = maxf(0, velocity.y)
			if horizontal_speed < 1: velocity.y = 1.5
	var flap_target := 1.0 if velocity.y > 0.4 or climb else (0.7 if forward > 0 and horizontal_speed < target_speed * 0.8 else (0.25 if forward > 0 and not boost else 0.0))
	flap = lerpf(flap, flap_target, minf(1, dt * 5))
	var old_flap := int(step_phase)
	if flap > 0.45: step_phase += dt * (1.8 + flap * 2.2)
	if old_flap != int(step_phase): _play_sound("wing")
	var flight_speed := velocity.length()
	var target_heading := atan2(velocity.x, -velocity.z) if flight_speed > 1.5 else cam_yaw
	var turn := clampf(wrapf(target_heading - heading, -PI, PI) * 6, -4.5, 4.5)
	heading += turn * dt
	var climb_angle := asin(clampf(velocity.y / flight_speed, -1, 1)) if flight_speed > 1 else 0.0
	bird_pitch = lerpf(bird_pitch, clampf(climb_angle, -0.9, 0.7), minf(1, dt * 4))
	var target_bank := clampf(-turn * 0.22 - lateral * 0.35, -0.9, 0.9) * minf(1, flight_speed / 4)
	bank = lerpf(bank, target_bank, minf(1, dt * 4))
	_animate_gull(dt)

func _place_camera(dt: float, immediate := false) -> void:
	var bird := mode == "gull"
	var focus := position + Vector3(0, 0.25 if bird else 0.5, 0)
	var offset := Vector3(-sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	var distance := (3.4 if perched else 4.5) if bird else 4.2
	if (not bird or world.supports_surface_traversal) and is_inside_tree():
		var ray := PhysicsRayQueryParameters3D.create(focus, focus + offset * distance, 1, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): distance = clampf(focus.distance_to(hit.position) - 0.55, .35 if world.supports_surface_traversal else 1.3, 4.2)
		camera_distance = distance if immediate else lerpf(camera_distance, distance, minf(1, dt * (12 if distance < camera_distance else 2)))
		distance = camera_distance
	var destination := focus + offset * distance + Vector3(0, 0.315 if bird else 0.385, 0)
	var clearance := (1.6 if perched else 0.7) if bird else 1.1
	destination.y = maxf(destination.y, maxf(_height(destination.x, destination.z), flight_bounds.position.y) + clearance)
	camera.position = destination if immediate else camera.position.lerp(destination, 1 - exp(-dt * (5.5 if bird else 6.5)))
	if world.supports_surface_traversal:
		var final_ray := PhysicsRayQueryParameters3D.create(focus,camera.position,1,[get_rid()])
		var obstruction := get_world_3d().direct_space_state.intersect_ray(final_ray)
		if not obstruction.is_empty():camera.position = obstruction.position + (focus-obstruction.position).normalized()*.14
	camera_look = focus if immediate else camera_look.lerp(focus, 1 - exp(-dt * 9))
	camera.look_at(camera_look)
	camera.rotation.z += bank * 0.12 if bird else sin(elapsed * 9) * 0.0025 * minf(1, speed / 4)

func _material(hex: String) -> Material:
	if _materials.has(hex): return _materials[hex]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = 1
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_materials[hex] = material
	return material

func _group(parent: Node3D, at := Vector3.ZERO) -> Node3D:
	var result := Node3D.new()
	parent.add_child(result)
	result.position = at
	return result

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material, scale_value := Vector3.ONE) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.material_override = material
	result.position = at
	result.scale = scale_value
	parent.add_child(result)
	return result

func _sphere(parent: Node3D, at: Vector3, radius: float, material: Material, scale_value := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 12
	mesh.rings = 8
	return _mesh(parent, mesh, at, material, scale_value)

func _capsule(parent: Node3D, at: Vector3, radius: float, length: float, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length + radius * 2
	mesh.radial_segments = 10
	mesh.rings = 5
	return _mesh(parent, mesh, at, material)

func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, at, material)

func _cone(parent: Node3D, at: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = 0
	mesh.height = height
	mesh.radial_segments = 6
	return _mesh(parent, mesh, at, material)

func _build_cat() -> void:
	cat = _group(self)
	cat.name = "TabbyCat"
	cat.scale = Vector3.ONE * 1.35
	cat_body = _group(cat)
	var orange := _material("df8b3c")
	var cream := _material("f5e9d2")
	var stripe := _material("8a4a22")
	var green := _material("5ea34a")
	var black := _material("1a1410")
	var pink := _material("e9a3a0")
	_capsule(cat_body, Vector3(0, 0.26, 0), 0.105, 0.27, orange).rotation.x = PI / 2
	_capsule(cat_body, Vector3(0, 0.215, 0), 0.075, 0.22, cream).rotation.x = PI / 2
	_sphere(cat_body, Vector3(0, 0.28, 0.13), 0.11, orange)
	_sphere(cat_body, Vector3(0, 0.25, 0.2), 0.1, cream, Vector3(1, 0.8, 0.7))
	cat_head = _group(cat_body, Vector3(0, 0.36, 0.26))
	_sphere(cat_head, Vector3.ZERO, 0.11, orange, Vector3(1.05, 0.92, 0.95))
	_sphere(cat_head, Vector3(0, -0.03, 0.075), 0.052, cream, Vector3(1.25, 0.8, 1))
	_sphere(cat_head, Vector3(0, -0.012, 0.125), 0.012, pink)
	for side in [-1, 1]:
		var ear := _cone(cat_head, Vector3(side * 0.065, 0.1, -0.01), 0.04, 0.08, orange)
		ear.rotation = Vector3(-0.2, 0, -side * 0.35)
		var inner := _cone(cat_head, Vector3(side * 0.065, 0.095, 0), 0.02, 0.05, pink)
		inner.rotation = ear.rotation
		_sphere(cat_head, Vector3(side * 0.045, 0.015, 0.09), 0.017, green)
		_sphere(cat_head, Vector3(side * 0.045, 0.015, 0.104), 0.008, black)
		_box(cat_head, Vector3(side * 0.06, 0.05, 0.03), Vector3(0.02, 0.006, 0.05), stripe).rotation.y = side * 0.5
	for index in 4:
		_box(cat_body, Vector3(0, 0.362, 0.1 - index * 0.07), Vector3(0.11, 0.006, 0.014), stripe).rotation.z = 0.08 if index % 2 else -0.08
	for index in 4:
		var x := -0.06 if index % 2 == 0 else 0.06
		var z := 0.13 if index < 2 else -0.12
		var hip := _group(cat_body, Vector3(x, 0.24, z))
		_capsule(hip, Vector3(0, -0.07, 0), 0.03, 0.12, orange)
		var knee := _group(hip, Vector3(0, -0.14, 0))
		_capsule(knee, Vector3(0, -0.05, 0), 0.024, 0.09, orange)
		_sphere(knee, Vector3(0, -0.1, 0.012), 0.03, cream, Vector3(1, 0.7, 1.2))
		cat_legs.append({"hip": hip, "knee": knee, "front": index < 2, "side": index % 2})
	var previous := cat_body
	for index in 7:
		var joint := _group(previous, Vector3(0, 0.3, -0.19) if index == 0 else Vector3(0, 0, -0.06))
		_capsule(joint, Vector3(0, 0, -0.03), 0.028 - index * 0.002, 0.05, stripe if index % 2 else orange).rotation.x = PI / 2
		cat_tail.append(joint)
		previous = joint

func _animate_cat(dt: float) -> void:
	var running := minf(1, speed / 5.5)
	if speed > 0.2: gait_phase += dt * (6 + speed * 2.2)
	var amplitude := 0.25 + running * 0.65
	for leg in cat_legs:
		var phase := gait_phase + (0.0 if leg.front else PI * 0.9) + (0.35 if leg.side else 0.0)
		leg.hip.rotation.x = sin(phase) * amplitude * (1.0 if leg.front else 1.1)
		leg.knee.rotation.x = maxf(0, -cos(phase)) * amplitude * 1.2 * (1.0 if leg.front else -0.5) + (0.1 if leg.front else -0.15)
		if not grounded:
			leg.hip.rotation.x = -0.9 if leg.front else 0.8
			leg.knee.rotation.x = 0.6 if leg.front else -0.6
	cat_body.position.y = absf(sin(gait_phase)) * 0.035 * running + (sin(elapsed * 2.2) * 0.004 if speed < 0.2 else 0)
	cat_body.rotation.x = sin(gait_phase) * 0.07 * running
	cat_head.rotation.x = -0.15 - sin(gait_phase) * 0.06 * running + (sin(elapsed * 1.3) * 0.05 if speed < 0.2 else 0)
	cat_head.rotation.y = sin(elapsed * 0.7) * 0.35 if speed < 0.2 else 0
	for index in cat_tail.size():
		cat_tail[index].rotation.x = 0.35 - index * 0.02 + sin(elapsed * 3 + index * 0.6) * 0.12 * (0.5 + running) + (0.4 if index == 0 else 0.0)
		cat_tail[index].rotation.y = sin(elapsed * 2.2 + index * 0.8) * 0.18

func _build_gull() -> void:
	gull = _group(self)
	gull.name = "Seagull"
	gull.scale = Vector3.ONE * 1.25
	gull_body = _group(gull)
	var white := _material("f6f3ea")
	var grey := _material("a9b1b8")
	var black := _material("2a2a2e")
	var yellow := _material("e8b64a")
	var red := _material("d0503a")
	var body := _capsule(gull_body, Vector3.ZERO, 0.085, 0.24, white)
	body.rotation.x = PI / 2
	body.scale.y = 0.9
	var back := _capsule(gull_body, Vector3(0, 0.035, -0.01), 0.07, 0.2, grey)
	back.rotation.x = PI / 2
	back.scale = Vector3(1.05, 0.7, 1)
	gull_head = _group(gull_body, Vector3(0, 0.055, 0.2))
	_sphere(gull_head, Vector3.ZERO, 0.068, white, Vector3(0.95, 0.95, 1.1))
	_cone(gull_head, Vector3(0, -0.012, 0.11), 0.022, 0.09, yellow).rotation.x = PI / 2
	_sphere(gull_head, Vector3(0, -0.022, 0.12), 0.008, red)
	for side in [-1, 1]: _sphere(gull_head, Vector3(side * 0.045, 0.02, 0.045), 0.011, black)
	gull_tail = _group(gull_body, Vector3(0, 0, -0.16))
	_box(gull_tail, Vector3(0, 0, -0.07), Vector3(0.14, 0.012, 0.14), white)
	_box(gull_tail, Vector3(0, 0, -0.135), Vector3(0.15, 0.014, 0.03), black)
	for side in [-1, 1]:
		var shoulder := _group(gull_body, Vector3(side * 0.06, 0.05, 0.02))
		_box(shoulder, Vector3(side * 0.17, 0, -0.02), Vector3(0.34, 0.012, 0.19), grey)
		_box(shoulder, Vector3(side * 0.17, -0.002, -0.14), Vector3(0.34, 0.01, 0.06), white)
		var elbow := _group(shoulder, Vector3(side * 0.34, 0, 0))
		_box(elbow, Vector3(side * 0.16, 0, -0.05), Vector3(0.32, 0.01, 0.15), grey)
		_box(elbow, Vector3(side * 0.29, 0, -0.07), Vector3(0.1, 0.011, 0.12), black)
		gull_wings.append({"shoulder": shoulder, "elbow": elbow, "side": side})
		var leg := _group(gull_body, Vector3(side * 0.035, -0.05, -0.03))
		_capsule(leg, Vector3(0, -0.05, 0), 0.008, 0.084, yellow)
		_box(leg, Vector3(0, -0.1, 0.015), Vector3(0.04, 0.008, 0.05), yellow)
		gull_legs.append(leg)

func _animate_gull(dt: float) -> void:
	gull.rotation = Vector3(-bird_pitch, PI - heading, -bank)
	animated_flap = lerpf(animated_flap, 0.0 if perched else flap, minf(1, dt * 6))
	animated_perch = lerpf(animated_perch, float(perched), minf(1, dt * 5))
	flap_phase += dt * (5.5 + animated_flap * 6.5) * TAU / 3
	var wave := sin(flap_phase)
	var perch := animated_perch
	for wing in gull_wings:
		var angle := 0.12 + sin(elapsed * 1.7) * 0.03 + wave * 0.75 * animated_flap
		wing.shoulder.rotation.z = -wing.side * (angle * (1 - perch) + 1.35 * perch)
		wing.shoulder.rotation.y = wing.side * 0.55 * perch
		var lag := sin(flap_phase - 0.9)
		wing.elbow.rotation.z = -wing.side * ((0.05 + maxf(0, -lag) * 0.55 * animated_flap + lag * 0.15 * animated_flap) * (1 - perch) + 0.9 * perch)
		wing.elbow.rotation.y = -wing.side * 0.5 * perch
	gull_body.position.y = (wave * 0.012 * animated_flap + sin(elapsed * 1.3) * 0.006) * (1 - perch)
	gull_body.rotation.x = (-0.05 - wave * 0.04 * animated_flap) * (1 - perch) + 0.35 * perch
	gull_head.rotation.x = (0.15 + wave * 0.05 * animated_flap) * (1 - perch) - 0.25 * perch + (sin(elapsed * 0.9) * 0.08 if perch > 0.5 else 0)
	gull_head.rotation.y = sin(elapsed * 0.6) * 0.5 if perch > 0.5 else 0
	gull_tail.rotation.x = 0.1 + sin(elapsed * 2.1) * 0.04 - 0.35 * perch
	for leg in gull_legs:
		leg.rotation.x = -1.3 * (1 - perch)
		leg.position.y = -0.05 - 0.02 * perch

func _start_audio() -> void:
	# Entire soundscape is synthesized at runtime; no sound files are loaded.
	audio = AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050
	generator.buffer_length = 0.15
	audio.stream = generator
	audio.volume_db = -6
	add_child(audio)
	audio.play()
	audio_playback = audio.get_stream_playback()

func _play_sound(kind: String) -> void:
	if audio == null or menu_open or shot_mode: return
	sound_events.append({"kind": kind, "start": audio_time, "phase": 0.0, "seed": randf()})

func _process(_delta: float) -> void:
	if audio_playback == null or menu_open: return
	# Maps select their soundscape; the shared synthesizer also serves character sounds.
	var wind_gain := float(ambience.get("wind_gain", 0.0))
	var wave_base := float(ambience.get("wave_base", 0.0))
	var wave_swell := float(ambience.get("wave_swell", 0.0))
	var cicada_frequencies: Vector2 = ambience.get("cicada_frequencies", Vector2.ZERO)
	var cicada_gain := float(ambience.get("cicada_gain", 0.0))
	var frames := audio_playback.get_frames_available()
	for index in frames:
		audio_time += 1.0 / 22050.0
		var noise := randf_range(-1, 1)
		audio_noise = audio_noise * 0.975 + noise * 0.025
		var sea := wave_base + wave_swell * sin(audio_time * 0.55) * sin(audio_time * 0.137 + 1.3)
		var sample_value := audio_noise * (wind_gain + sea * 4)
		# Summer cicadas: several gently beating high partials, softened by distance.
		var cicada := (sin(audio_time * TAU * cicada_frequencies.x) + sin(audio_time * TAU * cicada_frequencies.y)) * cicada_gain
		sample_value += cicada * (0.45 + 0.55 * pow(sin(audio_time * 33), 2))
		for sound in sound_events:
			var age: float = audio_time - sound.start
			var envelope := 0.0
			var frequency := 0.0
			match sound.kind:
				"step": sample_value += noise * exp(-age * 55) * 0.028
				"wing": sample_value += audio_noise * sin(clampf(age / 0.28, 0, 1) * PI) * 0.35 if age < 0.28 else 0
				"meow":
					if age < 0.48:
						frequency = (560 + sound.seed * 100) * (lerpf(1, 1.45, age / 0.12) if age < 0.12 else lerpf(1.45, 0.8, (age - 0.12) / 0.36)) + sin(age * TAU * 28) * 18
						envelope = minf(age / 0.05, 1) * minf((0.48 - age) / 0.2, 1) * 0.03
				"cry", "bird":
					var syllable := fmod(age, 0.36)
					if age < 1.05 and syllable < 0.29:
						frequency = (1120 + sound.seed * 160) * (0.85 + 0.4 * sin(syllable / 0.29 * PI)) + sin(age * TAU * 38) * 45
						envelope = sin(syllable / 0.29 * PI) * (0.023 if sound.kind == "cry" else 0.008)
			if frequency > 0:
				sound.phase += frequency * TAU / 22050
				sample_value += (sin(sound.phase) + sin(sound.phase * 2) * 0.25 + sin(sound.phase * 3) * 0.15) * envelope
		audio_playback.push_frame(Vector2(sample_value, sample_value * 0.97))
	sound_events = sound_events.filter(func(event: Dictionary) -> bool: return audio_time - event.start < 1.1)
	if bool(ambience.get("birds", false)) and audio_time > next_bird:
		_play_sound("bird")
		next_bird = audio_time + randf_range(8, 19)
