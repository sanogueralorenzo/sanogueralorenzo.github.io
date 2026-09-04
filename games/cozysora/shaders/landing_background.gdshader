shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 p = UV;
	vec3 cream = vec3(0.966, 0.956, 0.907);
	vec3 sage = vec3(0.874, 0.920, 0.855);
	vec3 color = mix(cream, sage, smoothstep(0.2, 1.2, p.y) * 0.40);
	float sun = exp(-length((p - vec2(0.86, 0.12)) * vec2(1.0, 1.25)) * 6.0);
	color = mix(color, vec3(1.0, 0.923, 0.722), sun * 0.38);
	float contours = abs(sin(p.x * 9.0 + p.y * 13.0 + sin(p.x * 4.0) * 2.0));
	float line = 1.0 - smoothstep(0.015, 0.025, contours);
	color -= line * 0.014 * smoothstep(0.42, 1.0, p.y);
	COLOR = vec4(color, 1.0);
}
