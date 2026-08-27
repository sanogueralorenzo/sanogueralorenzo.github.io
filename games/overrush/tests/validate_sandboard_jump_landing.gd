extends SceneTree

const ACCELERATION_FRAMES := 900
const LANDING_TIMEOUT_FRAMES := 1800

var _landing_rating := &""
var _landing_score := 0.0
var _landing_impact := 0.0
var _jump_velocity := Vector3.ZERO
var _jump_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://freeride.tscn").instantiate()
	scene.set_meta(&"overrush_manual_start", true)
	scene.get_node("Desert").seed = 41777
	root.add_child(scene)
	await physics_frame
	var rider: Sandboarder = scene.get_node("Sandboarder")
	rider.jumped.connect(_on_jumped.bind(rider))
	rider.landing_scored.connect(_on_landing_scored)
	scene.begin_run()
	Input.action_press(OverrushInputBindings.MOVE_FORWARD)
	for _frame in range(ACCELERATION_FRAMES):
		await physics_frame
	if not rider.is_on_floor():
		_fail(scene, "The rider should be in stable sand contact before the jump test.")
		return
	var pre_jump_speed := rider.get_horizontal_speed()
	if pre_jump_speed < 12.0:
		_fail(scene, "The jump test needs meaningful approach momentum, measured %.1f m/s." % pre_jump_speed)
		return
	if not rider.surface_trail.emitting:
		_fail(scene, "Grounded speed should emit a continuous surface trail.")
		return
	var visual_alignment := rider.board_visual.global_basis.y.normalized().dot(rider.get_floor_normal())
	if visual_alignment < 0.82:
		_fail(scene, "The board visual should align to the contacted sand normal: %.3f." % visual_alignment)
		return
	_landing_rating = &""
	_landing_score = 0.0
	_landing_impact = 0.0

	Input.action_press(OverrushInputBindings.HOP)
	await physics_frame
	Input.action_release(OverrushInputBindings.HOP)
	await physics_frame
	if _jump_count != 1 or rider.is_on_floor():
		_fail(scene, "A deliberate jump press should produce exactly one immediate takeoff.")
		return
	if Vector2(_jump_velocity.x, _jump_velocity.z).length() < pre_jump_speed * 0.97:
		_fail(scene, "Jumping should preserve approach momentum instead of replacing it.")
		return
	if _jump_velocity.dot(Vector3.UP) < 8.0:
		_fail(scene, "Jump launch should add a clear terrain-normal impulse.")
		return

	var boost_applied := rider.try_air_boost(rider.get_camera_relative_direction())
	if not boost_applied or rider.air_boost_state.available:
		_fail(scene, "The airborne correction should spend the single boost charge.")
		return

	for _frame in range(LANDING_TIMEOUT_FRAMES):
		await physics_frame
		if not _landing_rating.is_empty():
			break
	Input.action_release(OverrushInputBindings.MOVE_FORWARD)
	if _landing_rating.is_empty():
		_fail(scene, "The boosted jump did not resolve to a scored rideable landing.")
		return
	if not rider.air_boost_state.available or rider.air_boost_state.airborne:
		_fail(
			scene,
			"A scored rideable landing should restore exactly one grounded boost charge (available=%s, airborne=%s, on_floor=%s)."
			% [str(rider.air_boost_state.available), str(rider.air_boost_state.airborne), str(rider.is_on_floor())],
		)
		return
	if _landing_rating not in [SandboardMotion.LANDING_CLEAN, SandboardMotion.LANDING_SOLID, SandboardMotion.LANDING_ROUGH]:
		_fail(scene, "The landing should resolve to one documented quality rating.")
		return
	if _landing_score <= 0.0 or _landing_impact <= 0.0:
		_fail(scene, "Landing feedback should include meaningful quality and impact values.")
		return
	if not rider.landing_burst.emitting:
		_fail(scene, "A valid rideable landing should emit an immediate contact burst.")
		return
	var landing_text: String = scene.get_node("HUD/LandingFeedback").text
	if "LANDING" not in landing_text:
		_fail(scene, "The minimal HUD should communicate the resolved landing quality.")
		return
	print(
		"Sandboard jump/landing passed — %.1f m/s takeoff preserved, one boost spent/refreshed, %s landing (%.0f%%, %.1f m/s impact)."
		% [pre_jump_speed, _landing_rating, _landing_score * 100.0, _landing_impact]
	)
	scene.queue_free()
	await process_frame
	quit(0)


func _on_jumped(rider: Sandboarder) -> void:
	_jump_count += 1
	_jump_velocity = rider.velocity


func _on_landing_scored(rating: StringName, score: float, impact_speed: float) -> void:
	_landing_rating = rating
	_landing_score = score
	_landing_impact = impact_speed


func _fail(scene: Node, message: String) -> void:
	Input.action_release(OverrushInputBindings.MOVE_FORWARD)
	Input.action_release(OverrushInputBindings.HOP)
	Input.action_release(OverrushInputBindings.AIR_BOOST)
	push_error(message)
	scene.queue_free()
	await process_frame
	quit(1)
