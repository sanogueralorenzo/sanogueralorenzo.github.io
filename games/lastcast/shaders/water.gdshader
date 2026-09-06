shader_type spatial;
render_mode cull_back;
// Long, restrained ripples leave the bright highlights to the lure and wake.
uniform vec4 shallow : source_color = vec4(0.09, 0.46, 0.53, 1.0);
uniform vec4 deep : source_color = vec4(0.035, 0.255, 0.37, 1.0);
uniform float wind = 1.0;
// Forward+ reverse Z depth is already in [0, 1]. Only screen XY needs remapping.
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
varying vec3 world;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// Value noise with its analytic gradient; overlapping directions break regular wave rows.
vec3 wave_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash(i), b = hash(i + vec2(1, 0));
	float c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
	return vec3(mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
		du.x * mix(b - a, d - c, u.y), du.y * mix(c - a, d - b, u.x));
}
float school(vec2 p, vec2 center, float phase) {
	if (length(p - center) > 3.8) { return 0.0; }
	float silhouette = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i), t = TIME * .23 + phase + fi * .55;
		vec2 fish_center = center + vec2(sin(t) * 1.1 + (fi - 1.5) * .55, cos(t * .8) * .65 + sin(fi * 2.1) * .95);
		vec2 q = p - fish_center;
		float angle = sin(t) * .6 + .8;
		vec2 r = vec2(q.x * cos(angle) - q.y * sin(angle), q.x * sin(angle) + q.y * cos(angle));
		float body = 1.0 - smoothstep(.83, 1.16, length(r / vec2(.13, .38)));
		float tail_width = max(0.0, (-r.y - .30) * .60);
		float tail = smoothstep(.30, .38, -r.y) * (1.0 - smoothstep(.59, .63, -r.y)) * (1.0 - smoothstep(tail_width, tail_width + .035, abs(r.x)));
		silhouette = max(silhouette, max(body, tail * .72) * (.70 + .30 * sin(t + fi) * sin(t + fi)));
	}
	return silhouette;
}
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Keep the transparent sheet planar: waves belong to normals and buoyancy.
	// Coarse displaced transparent triangles otherwise cross shallow effects.
}
void fragment() {
	vec2 p = world.xz;
	float distance_to_camera = length(world - CAMERA_POSITION_WORLD);
	float scene_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	float thickness = max(0.0, -behind.z / behind.w + VERTEX.z);
	float shoal = exp(-thickness * .20);
	float broad = noise(p * .075);
	vec3 col = mix(deep.rgb, shallow.rgb, shoal * .82 + broad * .045);
	// Irregular cross-ripples, with no continuous sine train spanning the horizon.
	float close = 1.0 - smoothstep(22.0, 95.0, distance_to_camera);
	vec3 long_wave = wave_noise(p * vec2(1.10, 2.75) + vec2(TIME * .12, -TIME * .19));
	vec2 rotated = vec2(p.x * .80 + p.y * .60, p.x * -.60 + p.y * .80);
	vec3 fine_wave = wave_noise(rotated * vec2(3.40, 4.30) + vec2(-TIME * .22, TIME * .15));
	vec2 fine_gradient = vec2(fine_wave.y * .80 - fine_wave.z * .60, fine_wave.y * .60 + fine_wave.z * .80);
	vec2 slope = long_wave.yz * vec2(.047, .062) * (.40 + .60 * close) + fine_gradient * .028 * close;
	vec3 normal_world = normalize(vec3(slope.x * wind, 1.0, slope.y * wind));
	NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
	float fish = max(max(school(p, vec2(-12, 9), 0.0), school(p, vec2(0, 12), 2.0)), max(school(p, vec2(9, 24), 4.0), school(p, vec2(-13, 30), 7.0)));
	col *= 1.0 - fish * .45;
	ALBEDO = col;
	ROUGHNESS = .26;
	METALLIC = 0.0;
	SPECULAR = .36;
	// Actual transparency exposes a sloping seabed; glancing views remain reflective.
	float facing = clamp(dot(normalize(CAMERA_POSITION_WORLD - world), normal_world), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.0);
	// Beer–Lambert absorption follows the actual seabed and submerged hull/piles.
	ALPHA = clamp(1.0 - exp(-thickness * .65) + fresnel * .30 + fish * .07, .06, .98);
}
