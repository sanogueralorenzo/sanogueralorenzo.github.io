shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;


void fragment() {
	float distance_from_center = length(UV - vec2(0.5)) * 2.0;
	float inner_edge = smoothstep(0.72, 0.82, distance_from_center);
	float outer_edge = 1.0 - smoothstep(0.9, 1.0, distance_from_center);
	float ring = inner_edge * outer_edge;
	vec3 energy = vec3(0.015, 0.46, 0.78);
	ALBEDO = energy;
	EMISSION = energy * 1.45;
	ALPHA = ring * 0.18;
}
