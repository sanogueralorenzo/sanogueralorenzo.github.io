class_name RouteLookup
extends RefCounted

const BUCKET_SIZE := 20.0


class Query:
	var valid := false
	var position := Vector3.ZERO
	var tangent := Vector3.FORWARD
	var width := 1.0
	var bank := 0.0
	var bowl_depth := 0.0
	var narrow_pass_weight := 0.0
	var progress := 0.0
	var feature := ""
	var distance := INF
	var signed_distance := 0.0


var _positions := PackedVector3Array()
var _tangents := PackedVector3Array()
var _widths := PackedFloat32Array()
var _banks := PackedFloat32Array()
var _bowl_depths := PackedFloat32Array()
var _narrow_weights := PackedFloat32Array()
var _progress_values := PackedFloat32Array()
var _features := PackedStringArray()
var _bucket_segments := PackedInt32Array()
var _first_z := 0.0
var _last_z := 0.0


func configure(samples: Array[Dictionary]) -> void:
	var count := samples.size()
	_positions.resize(count)
	_tangents.resize(count)
	_widths.resize(count)
	_banks.resize(count)
	_bowl_depths.resize(count)
	_narrow_weights.resize(count)
	_progress_values.resize(count)
	_features.resize(count)
	for index in range(count):
		var sample: Dictionary = samples[index]
		_positions[index] = sample.position
		_tangents[index] = sample.tangent
		_widths[index] = sample.get("blend_width", sample.width)
		_banks[index] = sample.bank
		_bowl_depths[index] = sample.bowl_depth
		_narrow_weights[index] = sample.narrow_pass_weight
		_progress_values[index] = sample.progress
		_features[index] = sample.feature
	_build_buckets()


func sample(x: float, z: float, result: Query) -> void:
	result.valid = false
	if _positions.size() < 2:
		return
	if z >= _first_z:
		_fill_endpoint_query(0, x, z, result)
		return
	if z <= _last_z:
		_fill_endpoint_query(_positions.size() - 1, x, z, result)
		return

	var bucket := clampi(floori((_first_z - z) / BUCKET_SIZE), 0, _bucket_segments.size() - 1)
	var segment_index := _bucket_segments[bucket]
	while segment_index > 0 and z > _positions[segment_index].z:
		segment_index -= 1
	while segment_index + 1 < _positions.size() - 1 and z < _positions[segment_index + 1].z:
		segment_index += 1

	var first_position := _positions[segment_index]
	var second_position := _positions[segment_index + 1]
	var segment_t := inverse_lerp(first_position.z, second_position.z, z)
	result.valid = true
	result.position = first_position.lerp(second_position, segment_t)
	result.tangent = _tangents[segment_index].lerp(_tangents[segment_index + 1], segment_t).normalized()
	result.width = lerpf(_widths[segment_index], _widths[segment_index + 1], segment_t)
	result.bank = lerpf(_banks[segment_index], _banks[segment_index + 1], segment_t)
	result.bowl_depth = lerpf(_bowl_depths[segment_index], _bowl_depths[segment_index + 1], segment_t)
	result.narrow_pass_weight = lerpf(_narrow_weights[segment_index], _narrow_weights[segment_index + 1], segment_t)
	result.progress = lerpf(_progress_values[segment_index], _progress_values[segment_index + 1], segment_t)
	result.feature = _features[segment_index] if segment_t < 0.5 else _features[segment_index + 1]
	_set_query_distance(x, z, result)


func _fill_endpoint_query(index: int, x: float, z: float, result: Query) -> void:
	result.valid = true
	result.position = _positions[index]
	result.tangent = _tangents[index]
	result.width = _widths[index]
	result.bank = _banks[index]
	result.bowl_depth = _bowl_depths[index]
	result.narrow_pass_weight = _narrow_weights[index]
	result.progress = _progress_values[index]
	result.feature = _features[index]
	_set_query_distance(x, z, result)


func _set_query_distance(x: float, z: float, result: Query) -> void:
	var offset := Vector2(x - result.position.x, z - result.position.z)
	var lateral := Vector2(-result.tangent.z, result.tangent.x).normalized()
	result.distance = offset.length()
	result.signed_distance = offset.dot(lateral)


func _build_buckets() -> void:
	_bucket_segments.clear()
	if _positions.size() < 2:
		return
	_first_z = _positions[0].z
	_last_z = _positions[-1].z
	var bucket_count := maxi(1, ceili((_first_z - _last_z) / BUCKET_SIZE) + 1)
	_bucket_segments.resize(bucket_count)
	var segment_index := 0
	for bucket in range(bucket_count):
		var bucket_z := maxf(_last_z, _first_z - bucket * BUCKET_SIZE)
		while segment_index + 1 < _positions.size() - 1 and _positions[segment_index + 1].z > bucket_z:
			segment_index += 1
		_bucket_segments[bucket] = segment_index
