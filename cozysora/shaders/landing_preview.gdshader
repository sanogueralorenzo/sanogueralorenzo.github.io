shader_type canvas_item;
render_mode unshaded;
uniform vec2 panel_size = vec2(600.0, 360.0);
uniform vec4 corners = vec4(18.0, 0.0, 0.0, 18.0);
varying vec2 local_position;
void vertex() {
	local_position = VERTEX;
}
void fragment() {
	vec4 color = texture(TEXTURE, UV);
	vec2 p = local_position;
	float r = p.x < panel_size.x * 0.5 ? (p.y < panel_size.y * 0.5 ? corners.x : corners.w) : (p.y < panel_size.y * 0.5 ? corners.y : corners.z);
	vec2 q = abs(p - panel_size * 0.5) - panel_size * 0.5 + r;
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	color.a *= 1.0 - smoothstep(-0.8, 0.4, d);
	COLOR = color;
}
