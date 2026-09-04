class_name CozyPlayer
extends CharacterBody3D
## Procedural cat and seagull characters, locomotion, camera, and synthesized audio.
signal mode_changed(mode: String)
signal menu_changed(open: bool)

const VIEWS = {
	"coast": [-8.0, -9.3, 1.05, -1.2, -0.06],
	"paddy": [55.2, -2.6, 0.25, -2.31, 0.29],
	"farm": [53.6, 60.2, 3.0, 2.98, 0.1],
	"rail": [19.2, 80.0, 2.7, -3.02, 0.41],
	"village": [-4.6, 74.7, 2.55, 1.32, 0.0],
	"alley": [-26.4, 77.9, 2.65, 3.55, 0.2],
	"vending": [-61.65, 26.2, 1.22, 1.571, 0.16],
	"viaduct": [-64.3, 58.6, 2.9, -1.95, 0.52],
	"shrine": [-0.7, 8.0, 5.7, -3.16, 0.48],
	"top": [0.0, 30.0, 140.0, 0.0, -1.5],
}
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
var ui: CanvasLayer
var audio: AudioStreamPlayer
var audio_playback: AudioStreamGeneratorPlayback
var audio_time := 0.0
var audio_noise := 0.0
var sound_events: Array[Dictionary] = []
var next_bird := 4.0
var _tap_until: Dictionary = {}

func setup(level: Node3D) -> void:
	world = level
	name = "Player"
	floor_snap_length = 0.25
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
	world.add_child(camera)
	camera.current = true
	position = Vector3(-6.4, _height(-6.4, 0.2), 0.2)
	var requested_view := ""
	for argument in OS.get_cmdline_user_args():
		if argument == "--shot": shot_mode = true
		if argument.begins_with("--view="): requested_view = argument.trim_prefix("--view=")
		if argument == "--gull" or argument == "--bird": mode = "gull"
	gull.visible = mode == "gull"
	cat.visible = mode == "cat"
	if mode == "gull":
		position.y += 3.0
		cam_pitch = 0.18
	if not requested_view.is_empty() and VIEWS.has(requested_view):
		set_view(requested_view)
	else:
		_place_camera(0.016, true)
	menu_open = not shot_mode
	ui = load("res://scripts/interface.gd").new()
	add_child(ui)
	ui.setup(self)
	_animate_cat(0)
	_animate_gull(0)
	if shot_mode: ui.hide()

func _height(x: float, z: float) -> float:
	return float(world.height_at(x, z))

func set_view(view_name: String) -> void:
	if not VIEWS.has(view_name): return
	var view: Array = VIEWS[view_name]
	fixed_view = true
	cat.hide()
	gull.hide()
	position = Vector3(view[0], view[2], view[1])
	camera.position = position + Vector3(0, 1.6801, 0)
	camera.rotation = Vector3(view[4], view[3], 0)

func set_mode(value: String) -> void:
	if fixed_view or mode == value: return
	if mode == "cat": last_cat_position = position
	mode = value
	velocity = Vector3.ZERO
	if mode == "gull":
		position.y = _height(position.x, position.z) + 1.2
		velocity.y = 1.5
		perched = false
		flap = 1
		_play_sound("cry")
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
	if shot_mode: return
	menu_open = open
	_tap_until.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if not open and audio == null: _start_audio()
	menu_changed.emit(open)

func _unhandled_input(event: InputEvent) -> void:
	if shot_mode: return
	if event is InputEventKey and event.pressed and not event.echo:
		# Retain quick taps across the input/physics boundary instead of dropping them.
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		_tap_until[code] = Time.get_ticks_msec()+100
		if event.keycode == KEY_ESCAPE:
			set_menu(not menu_open)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB and not menu_open:
			set_mode("gull" if mode == "cat" else "cat")
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not menu_open:
		cam_yaw += event.relative.x * 0.0022
		cam_pitch = clampf(cam_pitch + event.relative.y * 0.0016, -1.05 if mode == "gull" else 0.05, 1.15 if mode == "gull" else 1.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not menu_open and mode == "gull":
		_play_sound("cry")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and not shot_mode:
		set_menu(true)

func _key(code: int, alternate: int = 0) -> bool:
	return not menu_open and not shot_mode and (Input.is_physical_key_pressed(code) or int(_tap_until.get(code,0))>Time.get_ticks_msec() or (alternate != 0 and (Input.is_physical_key_pressed(alternate) or int(_tap_until.get(alternate,0))>Time.get_ticks_msec())))

func _physics_process(delta: float) -> void:
	if world == null or fixed_view: return
	var dt := minf(delta, 0.05)
	elapsed = 3.0 if shot_mode else elapsed + dt
	if mode == "cat": _update_cat(dt)
	else: _update_gull(dt)
	_place_camera(dt)

func _update_cat(dt: float) -> void:
	var horizontal := float(_key(KEY_D, KEY_RIGHT)) - float(_key(KEY_A, KEY_LEFT))
	var forward := float(_key(KEY_W, KEY_UP)) - float(_key(KEY_S, KEY_DOWN))
	var moving := horizontal != 0 or forward != 0
	var turn := clampf(wrapf(cam_yaw - heading, -PI, PI) * 12, -9, 9)
	heading += turn * dt
	var target_speed := (6.4 if _key(KEY_SHIFT) else 3.6) if moving else 0.0
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
	if _key(KEY_SPACE) and grounded:
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
	cat.rotation.x = -atan2(slope, 0.8) * 0.8
	_animate_cat(dt)

func _update_gull(dt: float) -> void:
	var forward := float(_key(KEY_W, KEY_UP)) - float(_key(KEY_S, KEY_DOWN))
	var lateral := float(_key(KEY_D, KEY_RIGHT)) - float(_key(KEY_A, KEY_LEFT))
	var climb := _key(KEY_SPACE)
	var descend := _key(KEY_C, KEY_CTRL)
	var boost := _key(KEY_SHIFT)
	var active_input := forward != 0 or lateral != 0 or climb or descend
	var response_pitch := signf(cam_pitch) * maxf(0, absf(cam_pitch) - 0.16) / 0.84
	var vertical := -sin(response_pitch * 1.35)
	var horizontal := sqrt(maxf(0, 1 - vertical * vertical))
	var direction := Vector3(sin(cam_yaw) * horizontal, vertical, -cos(cam_yaw) * horizontal)
	var flat_direction := Vector3(sin(cam_yaw), 0, -cos(cam_yaw))
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
			position.y = maxf(_height(position.x, position.z), -29.95) + 0.17
			_animate_gull(dt)
			return
	var target_speed := 17.0 if boost else 9.5
	var target := Vector3.ZERO
	if forward > 0: target += direction * target_speed
	elif forward < 0: target -= flat_direction * 3.5
	target += Vector3(cos(cam_yaw), 0, sin(cam_yaw)) * lateral * (5 if forward > 0 else 6)
	if climb: target.y += 4.5 if forward > 0 else 5.5
	if descend: target.y -= 6
	if not active_input: target = Vector3(sin(heading) * 3, -0.9, -cos(heading) * 3)
	velocity = velocity.lerp(target, minf(1, dt * (3.2 if active_input else 0.9)))
	if forward > 0 and direction.y < -0.3: velocity.y += direction.y * 4 * dt
	if position.y - _height(position.x, position.z) < 2.2: move_and_slide()
	else: position += velocity * dt
	position.x = clampf(position.x, -135, 135)
	position.z = clampf(position.z, -95, 118)
	if position.y > 110:
		position.y = 110
		velocity.y = minf(0, velocity.y)
	var floor_y := maxf(_height(position.x, position.z), -29.95) + 0.17
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
	if not bird and is_inside_tree():
		var ray := PhysicsRayQueryParameters3D.create(focus, focus + offset * distance, 1, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): distance = clampf(focus.distance_to(hit.position) - 0.55, 1.3, 4.2)
		camera_distance = distance if immediate else lerpf(camera_distance, distance, minf(1, dt * (12 if distance < camera_distance else 2)))
		distance = camera_distance
	var destination := focus + offset * distance + Vector3(0, 0.315 if bird else 0.385, 0)
	var clearance := (1.6 if perched else 0.7) if bird else 1.1
	destination.y = maxf(destination.y, maxf(_height(destination.x, destination.z), -30) + clearance)
	camera.position = destination if immediate else camera.position.lerp(destination, 1 - exp(-dt * (5.5 if bird else 6.5)))
	camera_look = focus if immediate else camera_look.lerp(focus, 1 - exp(-dt * 9))
	camera.look_at(camera_look)
	camera.rotation.z += bank * 0.12 if bird else sin(elapsed * 9) * 0.0025 * minf(1, speed / 4)

func _material(hex: String) -> Material:
	return world.mat(hex)

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
	if audio == null: return
	sound_events.append({"kind": kind, "start": audio_time, "phase": 0.0, "seed": randf()})

func _process(_delta: float) -> void:
	if audio_playback == null: return
	var frames := audio_playback.get_frames_available()
	for index in frames:
		audio_time += 1.0 / 22050.0
		var noise := randf_range(-1, 1)
		audio_noise = audio_noise * 0.975 + noise * 0.025
		var sea := 0.022 + 0.018 * sin(audio_time * 0.55) * sin(audio_time * 0.137 + 1.3)
		var sample_value := audio_noise * (0.12 + sea * 4)
		# Summer cicadas: several gently beating high partials, softened by distance.
		var cicada := (sin(audio_time * TAU * 3820) + sin(audio_time * TAU * 4075)) * 0.0018
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
	if audio_time > next_bird:
		_play_sound("bird")
		next_bird = audio_time + randf_range(8, 19)
