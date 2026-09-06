shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
uniform vec3 foam_color : source_color = vec3(.82745, .89804, .84706);
void fragment() {
	ALBEDO = foam_color;
	// MSAA can evaluate outside these subpixel triangles: never blend negative alpha.
	ALPHA = clamp(COLOR.a, 0.0, 1.0);
}
