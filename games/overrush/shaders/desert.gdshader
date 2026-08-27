shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec2 seed_offset = vec2(0.0);
uniform vec2 world_origin = vec2(0.0);
uniform vec3 shadow_sand : source_color = vec3(0.055, 0.065, 0.11);
uniform vec3 pale_sand : source_color = vec3(0.34, 0.155, 0.055);
uniform vec3 sunlit_sand : source_color = vec3(0.69, 0.345, 0.095);
uniform vec3 sandstone : source_color = vec3(0.17, 0.075, 0.065);

varying vec3 world_position;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	return mix(
		mix(hash(cell), hash(cell + vec2(1.0, 0.0)), local.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), local.x),
		local.y
	);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 p = world_position.xz + world_origin + seed_offset;
	float broad = noise(p * 0.0035);
	float ripples = noise(p * 0.044 + vec2(31.0, -17.0));
	float wind_lines = sin((p.x * 0.16 + p.y * 0.044) + ripples * 2.8) * 0.5 + 0.5;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float stone = smoothstep(0.34, 0.67, slope + (broad - 0.5) * 0.16);
	vec3 key_light_direction = normalize(vec3(-0.35, 0.74, 0.57));
	float key_light = smoothstep(0.42, 0.88, max(dot(world_normal, key_light_direction), 0.0));
	float wind_crest = smoothstep(0.76, 0.98, wind_lines) * (1.0 - smoothstep(0.22, 0.52, slope));
	vec3 sand = mix(pale_sand, sunlit_sand, broad * 0.68 + wind_lines * 0.18 + 0.08);
	sand = mix(shadow_sand, sand, 0.28 + key_light * 0.72);
	sand += wind_crest * vec3(0.095, 0.047, 0.012);
	vec3 rock = mix(shadow_sand * 0.62, sandstone, broad);
	ALBEDO = mix(sand, rock, stone);
	ROUGHNESS = mix(0.91 - wind_crest * 0.12, 0.82, stone);
	SPECULAR = mix(0.18, 0.08, stone);
}
