shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float map_size = 3200.0;
uniform float route_length = 1450.0;
uniform vec2 region_breaks = vec2(0.32, 0.66);
uniform float palette_phase = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

float random_value(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = random_value(cell);
	float b = random_value(cell + vec2(1.0, 0.0));
	float c = random_value(cell + vec2(0.0, 1.0));
	float d = random_value(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float fbm(vec2 point) {
	float value = 0.0;
	float amplitude = 0.5;
	mat2 rotation = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int octave = 0; octave < 5; octave++) {
		value += value_noise(point) * amplitude;
		point = rotation * point * 2.03 + vec2(19.1, 7.7);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 palette_offset = vec2(palette_phase, -palette_phase * 0.73);
	float broad_pattern = fbm((world_position.xz + palette_offset) * 0.0048);
	float fine_pattern = fbm((world_position.xz + palette_offset * 2.1) * 0.019 + vec2(31.0, -17.0));
	float micro_pattern = fbm((world_position.xz - palette_offset) * 0.052 + vec2(-9.0, 43.0));
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock_mask = smoothstep(0.18, 0.68, slope + (fine_pattern - 0.5) * 0.31);
	float progress = clamp(-world_position.z / max(route_length, 1.0), 0.0, 1.0);
	float verdant_weight = 1.0 - smoothstep(region_breaks.x - 0.075, region_breaks.x + 0.075, progress);
	float prism_weight = smoothstep(region_breaks.y - 0.075, region_breaks.y + 0.075, progress);
	float ember_weight = max(0.0, 1.0 - verdant_weight - prism_weight);

	// Verdant Reach: saturated greens and turquoise mineral veining.
	vec3 emerald = vec3(0.008, 0.22, 0.13);
	vec3 lime = vec3(0.32, 0.72, 0.055);
	vec3 verdant_ground = mix(emerald, lime, smoothstep(0.2, 0.88, broad_pattern));
	float turquoise_patch = smoothstep(0.58, 0.83, fine_pattern) * (1.0 - rock_mask);
	verdant_ground = mix(verdant_ground, vec3(0.015, 0.48, 0.5), turquoise_patch * 0.58);
	vec3 verdant_rock = mix(vec3(0.19, 0.035, 0.38), vec3(0.94, 0.12, 0.34), fine_pattern);

	// Ember Basin: warm ochre ground, coral strata, and plum rock faces.
	vec3 ember_ground = mix(vec3(0.32, 0.065, 0.025), vec3(0.93, 0.43, 0.045), broad_pattern);
	ember_ground = mix(ember_ground, vec3(0.92, 0.12, 0.20), smoothstep(0.62, 0.86, fine_pattern) * 0.45);
	vec3 ember_rock = mix(vec3(0.24, 0.018, 0.25), vec3(1.0, 0.52, 0.13), fine_pattern);

	// Prism Highlands: cool cyan flats with luminous lime and violet faces.
	vec3 prism_ground = mix(vec3(0.015, 0.21, 0.32), vec3(0.26, 0.68, 0.47), broad_pattern);
	prism_ground = mix(prism_ground, vec3(0.52, 0.83, 0.12), smoothstep(0.57, 0.82, fine_pattern) * 0.62);
	vec3 prism_rock = mix(vec3(0.075, 0.05, 0.42), vec3(0.86, 0.15, 0.72), fine_pattern);

	vec3 ground = verdant_ground * verdant_weight + ember_ground * ember_weight + prism_ground * prism_weight;
	vec3 rock = verdant_rock * verdant_weight + ember_rock * ember_weight + prism_rock * prism_weight;
	vec3 color = mix(ground, rock, rock_mask);
	color *= mix(0.82, 1.16, micro_pattern);
	color = mix(color, color * vec3(1.12, 0.86, 1.08), smoothstep(0.72, 0.91, fine_pattern) * 0.28);

	ALBEDO = color;
	ROUGHNESS = mix(0.92, 0.68, rock_mask);
	SPECULAR = 0.18;
}
