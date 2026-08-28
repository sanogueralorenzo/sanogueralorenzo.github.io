extends SceneTree

const EARLY_SIMULATION_FRAMES := 600
const TOTAL_SIMULATION_FRAMES := 2400

var _sampled_contact_frames := 0
var _grounded_contact_frames := 0
var _current_airtime_frames := 0
var _longest_airtime_frames := 0
var _airtime_episode_count := 0
var _landing_count := 0
var _rough_landing_count := 0
var _landing_observations: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://freeride.tscn").instantiate()
	scene.set_meta(&"overrush_manual_start", true)
	scene.get_node("Desert").seed = 41777
	root.add_child(scene)
	await physics_frame
	var world: ProceduralDesert = scene.get_node("Desert")
	var rider: Sandboarder = scene.get_node("Sandboarder")
	rider.landing_scored.connect(_on_landing_scored)
	var start_position := rider.global_position
	scene.begin_run()
	Input.action_press(OverrushInputBindings.MOVE_FORWARD)
	var peak_speed := 0.0
	for frame_index in range(EARLY_SIMULATION_FRAMES):
		await physics_frame
		peak_speed = maxf(peak_speed, rider.get_horizontal_speed())
		if frame_index >= 120:
			_sample_contact(rider)

	var planar_distance := Vector2(
		rider.global_position.x - start_position.x,
		rider.global_position.z - start_position.z
	).length()
	var descent := start_position.y - rider.global_position.y
	if planar_distance < 18.0:
		push_error("Sandboarder only travelled %.1f m after deliberate carve input." % planar_distance)
		await _finish(scene, 1)
		return
	if descent < 0.5:
		push_error("Sandboarder did not begin descending from the central summit: %.2f m." % descent)
		await _finish(scene, 1)
		return
	if rider.get_horizontal_speed() < 10.0:
		push_error("Slope-driven movement did not gather useful speed: %.1f m/s." % rider.get_horizontal_speed())
		await _finish(scene, 1)
		return
	for _frame in range(TOTAL_SIMULATION_FRAMES - EARLY_SIMULATION_FRAMES):
		await physics_frame
		peak_speed = maxf(peak_speed, rider.get_horizontal_speed())
		_sample_contact(rider)
	Input.action_release(OverrushInputBindings.MOVE_FORWARD)
	if peak_speed < 28.0:
		push_error(
			"Extended downhill carving never reached a satisfying speed: %.1f m/s across %.1f m (final y %.1f)."
			% [peak_speed, rider.distance_traveled, rider.global_position.y]
		)
		await _finish(scene, 1)
		return
	if rider.distance_traveled < 420.0:
		push_error("Extended downhill carving covered too little terrain: %.1f m." % rider.distance_traveled)
		await _finish(scene, 1)
		return
	_finalize_contact_sample()
	var grounded_ratio := float(_grounded_contact_frames) / float(_sampled_contact_frames)
	var longest_airtime := float(_longest_airtime_frames) / float(Engine.physics_ticks_per_second)
	if grounded_ratio < 0.93:
		push_error("Ordinary no-jump carving feels too floaty: only %.1f%% grounded." % (grounded_ratio * 100.0))
		await _finish(scene, 1)
		return
	if _airtime_episode_count < 1 or _airtime_episode_count > 2 or longest_airtime > 2.0:
		push_error(
			"Terrain following should preserve occasional readable natural launches, measured %d episodes with %.2f s longest."
			% [_airtime_episode_count, longest_airtime]
		)
		await _finish(scene, 1)
		return
	if _landing_count < 1 or _landing_count > 2:
		push_error("The no-jump contact envelope produced an unexpected %d scored landings." % _landing_count)
		await _finish(scene, 1)
		return
	var carve_track := scene.get_node("CarveTrack") as MeshInstance3D
	if rider._carve_track_points.size() != rider.carve_track_max_points:
		push_error(
			"The sustained carve track should fill and respect its %d-point residency bound: %d."
			% [rider.carve_track_max_points, rider._carve_track_points.size()]
		)
		await _finish(scene, 1)
		return
	if carve_track.mesh == null or carve_track.mesh.surface_get_array_len(0) != rider._carve_track_points.size() * 2:
		push_error("The terrain-conforming carve track should retain one bounded vertex pair per sample.")
		await _finish(scene, 1)
		return
	for point in rider._carve_track_points:
		var track_position := Vector3(point.position)
		var planar_track_distance := Vector2(
			track_position.x - rider.global_position.x,
			track_position.z - rider.global_position.z,
		).length()
		if planar_track_distance > 800.0:
			push_error("Floating-origin rebasing left a carve-track sample %.1f m behind local space." % planar_track_distance)
			await _finish(scene, 1)
			return
		var terrain_height := world.get_local_surface_height(track_position.x, track_position.z)
		if absf(track_position.y - terrain_height) > 0.12:
			push_error("A carve-track sample drifted %.3f m away from its terrain surface." % absf(track_position.y - terrain_height))
			await _finish(scene, 1)
			return
	print(
		"Sandboard motion passed — %.1f m early travel, %.1f m early descent, %.1f m/s peak across %.1f m with a bounded %d-point carve track; %.1f%% grounded, %d air episodes, %.2f s longest, %d/%d rough landings."
		% [
			planar_distance,
			descent,
			peak_speed,
			rider.distance_traveled,
			rider._carve_track_points.size(),
			grounded_ratio * 100.0,
			_airtime_episode_count,
			longest_airtime,
			_rough_landing_count,
			_landing_count,
		]
	)
	print("Natural landing observations: %s" % ", ".join(_landing_observations))
	await _finish(scene, 0)


func _finish(scene: Node, exit_code: int) -> void:
	scene.queue_free()
	await process_frame
	quit(exit_code)


func _sample_contact(rider: Sandboarder) -> void:
	_sampled_contact_frames += 1
	if rider.is_on_floor():
		_grounded_contact_frames += 1
		if _current_airtime_frames > 0:
			_airtime_episode_count += 1
			_longest_airtime_frames = maxi(_longest_airtime_frames, _current_airtime_frames)
			_current_airtime_frames = 0
	else:
		_current_airtime_frames += 1


func _finalize_contact_sample() -> void:
	if _current_airtime_frames <= 0:
		return
	_airtime_episode_count += 1
	_longest_airtime_frames = maxi(_longest_airtime_frames, _current_airtime_frames)
	_current_airtime_frames = 0


func _on_landing_scored(rating: StringName, score: float, impact_speed: float) -> void:
	_landing_count += 1
	_landing_observations.append("%s %.0f%% %.1f m/s" % [rating, score * 100.0, impact_speed])
	if rating == SandboardMotion.LANDING_ROUGH:
		_rough_landing_count += 1
